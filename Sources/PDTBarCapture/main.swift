import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import ImageIO
import PDTBarSmokeProof

// Opt-in visual proof for the verify-pdtbar skill. Never requests TCC access:
// it only preflights Screen Recording and only drives the menu when AX is already trusted.

struct CheckResult {
    let name: String
    let ok: Bool
    let detail: String
}

struct CaptureCheck {
    let name: String
    let probe: () -> (ok: Bool, detail: String)
}

func runPreflight() -> (results: [CheckResult], firstFailure: CheckResult?) {
    let results = blockingChecks().map { check in
        let outcome = check.probe()
        return CheckResult(name: check.name, ok: outcome.ok, detail: outcome.detail)
    }
    return (results, results.first { !$0.ok })
}

func blockingChecks() -> [CaptureCheck] { [
    CaptureCheck(name: "ci") {
        guard let value = ProcessInfo.processInfo.environment["CI"], !value.isEmpty else {
            return (true, "not CI")
        }
        return (false, "CI=\(value)")
    },
    CaptureCheck(name: "console-session") {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool ?? false
        return onConsole ? (true, "on console") : (false, "session is not on the console")
    },
    CaptureCheck(name: "screen-unlocked") {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return locked ? (false, "screen is locked") : (true, "unlocked")
    },
    CaptureCheck(name: "display-awake") {
        CGDisplayIsAsleep(CGMainDisplayID()) == 0 ? (true, "main display awake") : (false, "main display asleep")
    },
    CaptureCheck(name: "screensaver") {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine"
                || $0.executableURL?.lastPathComponent == "ScreenSaverEngine"
        }
        return running ? (false, "screen saver running") : (true, "not running")
    },
    CaptureCheck(name: "screen-recording") {
        CGPreflightScreenCaptureAccess() ? (true, "granted") : (false, "not granted for this host process")
    },
] }

func accessibilityLine() -> String {
    AXIsProcessTrusted() ? "granted (menu can be opened)" : "not granted (capture needs it to find the status item on macOS 26)"
}

func requireCapture() {
    if let failure = runPreflight().firstFailure {
        print("can-capture: no (\(failure.name): \(failure.detail))")
        exit(3)
    }
}

// MARK: Windows

struct ScreenWindow {
    let id: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    let frame: CGRect
}

enum WindowLayer {
    static let status = Int(CGWindowLevelForKey(.statusWindow))
    static let popUpMenu = Int(CGWindowLevelForKey(.popUpMenuWindow))
}

func onScreenWindows() -> [ScreenWindow] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return info.compactMap { window in
        guard let id = window[kCGWindowNumber as String] as? Int,
              let owner = window[kCGWindowOwnerPID as String] as? Int,
              let layer = window[kCGWindowLayer as String] as? Int,
              (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDict),
              frame.width > 1, frame.height > 1
        else {
            return nil
        }
        return ScreenWindow(id: CGWindowID(id), ownerPID: pid_t(owner), layer: layer, frame: frame)
    }
}

func menuWindows(pid: pid_t) -> [ScreenWindow] {
    onScreenWindows().filter { $0.ownerPID == pid && $0.layer >= WindowLayer.popUpMenu }
}

/// macOS 26 draws status items in Control Center-owned windows, so the app may own none.
/// Then the AX frame of `pdtbar.status` picks the enclosing status-layer window.
func statusItemFrame(pid: pid_t, menu: StatusMenu?) -> CGRect? {
    let statusWindows = onScreenWindows().filter { $0.layer == WindowLayer.status }
    if let own = statusWindows.first(where: { $0.ownerPID == pid }) { return own.frame }
    guard let axFrame = menu?.statusFrame else { return nil }
    let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
    return statusWindows.first { $0.frame.contains(center) }?.frame ?? axFrame
}

func waitFor(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return condition()
}

func captureRect(status: CGRect, menus: [ScreenWindow]) -> CGRect {
    // Small pad keeps the menu's rounded edge but leaves neighboring windows out of frame.
    let union = menus.reduce(status) { $0.union($1.frame) }.insetBy(dx: -4, dy: -4)
    var displayID = CGMainDisplayID()
    var count: UInt32 = 0
    let center = CGPoint(x: status.midX, y: status.midY)
    _ = CGGetDisplaysWithPoint(center, 1, &displayID, &count)
    return union.intersection(CGDisplayBounds(displayID)).integral
}

// MARK: Accessibility

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var elements: [AXUIElement] = []
    for attribute in ["AXChildren", "AXExtrasMenuBar"] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            continue
        }
        if let children = value as? [AXUIElement] {
            elements.append(contentsOf: children)
        } else if CFGetTypeID(value) == AXUIElementGetTypeID() {
            elements.append(value as! AXUIElement)
        }
    }
    return elements
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID()
    else {
        return nil
    }
    return (value as! AXValue)
}

func findElement(in root: AXUIElement, limit: Int = 500, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
    var stack = [root]
    var visited = 0
    while let element = stack.popLast(), visited < limit {
        visited += 1
        if matches(element) { return element }
        stack.append(contentsOf: axChildren(element))
    }
    return nil
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = axValue(element, kAXPositionAttribute), let sizeValue = axValue(element, kAXSizeAttribute),
          AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size)
    else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

struct StatusMenu {
    let pid: pid_t
    let status: AXUIElement

    init?(pid: pid_t) {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // Pressing a status item can block until its menu stops tracking; keep AX calls short.
        _ = AXUIElementSetMessagingTimeout(app, 0.5)
        guard let status = findElement(in: app, where: { axString($0, "AXIdentifier") == "pdtbar.status" }) else {
            return nil
        }
        _ = AXUIElementSetMessagingTimeout(status, 0.5)
        self.pid = pid
        self.status = status
    }

    var statusFrame: CGRect? { axFrame(status) }

    func open() -> Bool {
        if !menuWindows(pid: pid).isEmpty { return true }
        for action in [kAXPressAction, kAXShowMenuAction] {
            _ = AXUIElementPerformAction(status, action as CFString)
            if waitFor(timeout: 3, { !menuWindows(pid: pid).isEmpty }) { return true }
        }
        return false
    }

    @discardableResult
    func close() -> Bool {
        if let menu = findElement(in: status, where: { axString($0, "AXRole") == (kAXMenuRole as String) }) {
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            if waitFor(timeout: 1, { menuWindows(pid: pid).isEmpty }) { return true }
        }
        let escape: CGKeyCode = 53
        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: escape, keyDown: keyDown)?.postToPid(pid)
        }
        return waitFor(timeout: 1.5) { menuWindows(pid: pid).isEmpty }
    }
}

// MARK: Capture

func screencapture(_ arguments: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = arguments
    return process
}

func rectArgument(_ rect: CGRect) -> String {
    "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(code)
}

struct BlankCheck {
    let ok: Bool
    let detail: String
}

func blankCheck(_ image: CGImage) -> BlankCheck {
    let side = 64
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { return BlankCheck(ok: false, detail: "could not decode pixels") }
    var lumas: [Double] = []
    for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 8 {
        lumas.append(0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2]))
    }
    guard let minLuma = lumas.min(), let maxLuma = lumas.max() else {
        return BlankCheck(ok: false, detail: "all transparent")
    }
    let range = String(format: "%.0f", maxLuma - minLuma)
    if maxLuma < 12 { return BlankCheck(ok: false, detail: "nearly all black (lumaRange=\(range))") }
    if maxLuma - minLuma < 16 { return BlankCheck(ok: false, detail: "nearly uniform (lumaRange=\(range))") }
    return BlankCheck(ok: true, detail: "ok (lumaRange=\(range), samples=\(lumas.count))")
}

func reportImage(_ url: URL) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        fail("no image written at \(url.path)")
    }
    let check = blankCheck(image)
    print("image: \(url.path)")
    print("size: \(image.width)x\(image.height)")
    print("blank-check: \(check.ok ? "" : "FAIL ")\(check.detail)")
    if !check.ok { exit(1) }
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

/// Opens the menu (when AX allows) long enough to measure the status item + menu rect.
func measure(pid: pid_t, wantMenu: Bool) -> (rect: CGRect, menu: StatusMenu?, note: String) {
    let menu = StatusMenu(pid: pid)
    guard let status = statusItemFrame(pid: pid, menu: menu) else {
        fail(AXIsProcessTrusted()
            ? "status item pdtbar.status not found for pid \(pid) (menu bar hidden or item overflowed?)"
            : "no app-owned status window and Accessibility not granted to locate the status item")
    }
    guard wantMenu else { return (captureRect(status: status, menus: []), nil, "closed (--closed)") }
    guard let menu else { return (captureRect(status: status, menus: []), nil, "closed (accessibility not granted)") }
    guard menu.open() else { return (captureRect(status: status, menus: []), nil, "closed (menu window did not appear)") }
    Thread.sleep(forTimeInterval: 0.3)
    return (captureRect(status: status, menus: menuWindows(pid: pid)), menu, "open")
}

func screenshot(pid: pid_t, out: URL, wantMenu: Bool) {
    requireCapture()
    let measured = measure(pid: pid, wantMenu: wantMenu)
    let capture = screencapture(["-x", "-R", rectArgument(measured.rect), out.path])
    do { try capture.run() } catch { fail("screencapture: \(error)") }
    capture.waitUntilExit()
    let closed = measured.menu?.close() ?? true
    print("menu: \(measured.note)")
    if !closed { print("warning: menu did not close; press Escape") }
    print("rect: \(rectArgument(measured.rect))")
    guard capture.terminationStatus == 0 else { fail("screencapture exited \(capture.terminationStatus)") }
    reportImage(out)
}

func record(pid: pid_t, seconds: Int, out: URL) {
    requireCapture()
    let measured = measure(pid: pid, wantMenu: true)
    measured.menu?.close()
    Thread.sleep(forTimeInterval: 0.3)
    let capture = screencapture(["-x", "-v", "-V", String(seconds), "-R", rectArgument(measured.rect), out.path])
    do { try capture.run() } catch { fail("screencapture: \(error)") }
    let start = Date()
    Thread.sleep(forTimeInterval: 0.7)
    let opened = measured.menu?.open() ?? false
    let holdUntil = start.addingTimeInterval(max(Double(seconds) - 0.5, 1.0))
    if opened {
        Thread.sleep(forTimeInterval: max(holdUntil.timeIntervalSinceNow, 0))
        measured.menu?.close()
    }
    capture.waitUntilExit()
    print("menu: \(opened ? "opened during clip" : measured.note)")
    print("rect: \(rectArgument(measured.rect))")
    guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else {
        fail("screencapture exited \(capture.terminationStatus); no movie at \(out.path)")
    }
    print("movie: \(out.path)")
}

func writePoster(movie out: URL) async {
    let asset = AVURLAsset(url: out)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let poster = out.deletingLastPathComponent()
        .appendingPathComponent(out.deletingPathExtension().lastPathComponent + "-poster.png")
    do {
        let duration = try await asset.load(.duration)
        print("duration: \(String(format: "%.2f", duration.seconds))s")
        let (image, _) = try await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.5))
        writePNG(image, to: poster)
    } catch {
        fail("poster frame: \(error)")
    }
    reportImage(poster)
}

// MARK: Menu walk

struct WalkStep: Encodable {
    let name: String
    let opened: Bool
    let via: String
    let missing: [String]
    let screenshot: String?
}

struct WalkReport: Encodable {
    let plan: String
    let fixture: String
    let steps: [WalkStep]
    let ok: Bool
}

/// Identifiers under `root` whose element is on screen inside one of `windows`. Closed submenus keep their
/// rows in the AX tree, so a frame check is what proves a row is visible where the walk expects it.
func visibleIdentifiers(under root: AXUIElement, inside windows: [CGRect]) -> Set<String> {
    var found: Set<String> = []
    _ = findElement(in: root, limit: 5000) { element in
        if let identifier = axString(element, "AXIdentifier"), !identifier.isEmpty, let frame = axFrame(element),
           windows.contains(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            found.insert(identifier)
        }
        return false
    }
    return found
}

func element(_ identifier: String, under root: AXUIElement) -> AXUIElement? {
    findElement(in: root, limit: 5000) { axString($0, "AXIdentifier") == identifier }
}

/// A submenu has opened once the app owns more menu-level windows than before.
func openSubmenu(_ opener: AXUIElement, pid: pid_t) -> String? {
    let baseline = menuWindows(pid: pid).count
    for action in [kAXPressAction, kAXShowMenuAction] {
        _ = AXUIElementPerformAction(opener, action as CFString)
        if waitFor(timeout: 1.5, { menuWindows(pid: pid).count > baseline }) { return action }
    }
    guard let frame = axFrame(opener) else { return nil }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    return waitFor(timeout: 2, { menuWindows(pid: pid).count > baseline }) ? "hover" : nil
}

func runScreencapture(_ arguments: [String]) -> Bool {
    let capture = screencapture(arguments)
    do { try capture.run() } catch { return false }
    capture.waitUntilExit()
    return capture.terminationStatus == 0
}

func loadImage(_ url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

/// Proof image on a flat grey ground: the status item cropped from the screen, and each PDTBar menu
/// captured by window id, so neither desktop content nor neighboring menu bar items reach the PNG.
/// Raw captures stay in a private temp dir; only the composite is published to `out`.
func shoot(
    pid: pid_t, status: CGRect, statusItem: CGRect, minMenus: Int, out: URL, beforeCapture: (() -> Void)? = nil
) -> String? {
    Thread.sleep(forTimeInterval: 0.3)
    beforeCapture?()
    let menus = menuWindows(pid: pid)
    guard menus.count >= minMenus else { return "expected \(minMenus) open menu windows at capture, saw \(menus.count)" }
    let rect = captureRect(status: status, menus: menus)
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("pdtbar-walk-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    } catch {
        return "cannot create \(scratch.path): \(error)"
    }
    let base = scratch.appendingPathComponent("base.png")
    guard runScreencapture(["-x", "-R", rectArgument(rect), base.path]), let screen = loadImage(base) else {
        return "screencapture of \(rectArgument(rect)) failed"
    }
    let scale = CGFloat(screen.width) / rect.width
    func pixels(_ frame: CGRect) -> CGRect {
        CGRect(
            x: (frame.minX - rect.minX) * scale, y: CGFloat(screen.height) - (frame.maxY - rect.minY) * scale,
            width: frame.width * scale, height: frame.height * scale
        )
    }
    guard let context = CGContext(
        data: nil, width: screen.width, height: screen.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return "cannot allocate composite"
    }
    let bounds = CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(bounds)
    context.saveGState()
    context.clip(to: pixels(statusItem))
    context.draw(screen, in: bounds)
    context.restoreGState()
    // macOS 26 captures a menu window together with its open submenus, at their union size.
    let group = menus.dropFirst().reduce(menus[0].frame) { $0.union($1.frame) }
    func fits(_ image: CGImage, _ frame: CGRect) -> Bool {
        abs(CGFloat(image.width) / scale - frame.width) <= 2 && abs(CGFloat(image.height) / scale - frame.height) <= 2
    }
    for window in menus {
        let shot = scratch.appendingPathComponent("window-\(window.id).png")
        guard runScreencapture(["-x", "-o", "-l", String(window.id), shot.path]), let image = loadImage(shot) else {
            return "screencapture of menu window \(window.id) failed"
        }
        if fits(image, group) {
            context.draw(image, in: pixels(group))
            break
        }
        guard fits(image, window.frame) else {
            return "menu window \(window.id) captured at \(image.width)x\(image.height)px, matching neither its frame nor the menu group"
        }
        context.draw(image, in: pixels(window.frame))
    }
    guard let composite = context.makeImage() else { return "cannot render composite" }
    let staged = scratch.appendingPathComponent("final.png")
    writePNG(composite, to: staged)
    do {
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: staged, to: out)
    } catch {
        return "cannot publish \(out.path): \(error)"
    }
    let check = blankCheck(composite)
    print("image: \(out.path) \(composite.width)x\(composite.height) blank-check: \(check.ok ? "" : "FAIL ")\(check.detail)")
    return check.ok ? nil : "blank image: \(check.detail)"
}

func closeMenu(_ menu: StatusMenu) {
    // A cancel or Escape can close only the open submenu, so try twice.
    if !menu.close() { menu.close() }
}

func walk(pid: pid_t, planName: String, fixture: String, outDir: URL) {
    guard let plan = MenuWalkPlan.named[planName] else {
        fail("unknown plan \(planName); known: \(MenuWalkPlan.named.keys.sorted().joined(separator: ", "))", code: 64)
    }
    guard URL(fileURLWithPath: fixture).lastPathComponent == plan.fixture else {
        fail("plan \(planName) needs fixture \(plan.fixture); this run uses \(fixture)")
    }
    if let failure = runPreflight().firstFailure {
        fail("menu-walk cannot capture the menu (\(failure.name): \(failure.detail))", code: 3)
    }
    guard AXIsProcessTrusted() else {
        fail("menu-walk cannot open the menu: Accessibility is not granted to this host process", code: 3)
    }
    guard let menu = StatusMenu(pid: pid), let status = statusItemFrame(pid: pid, menu: menu) else {
        fail("status item pdtbar.status not found for pid \(pid) (menu bar hidden or item overflowed?)")
    }
    let statusItem = menu.statusFrame ?? status
    do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) } catch {
        fail("cannot create \(outDir.path): \(error)")
    }

    var steps: [WalkStep] = []
    func record(_ name: String, opened: Bool, via: String, missing: [MenuSelector], shot: URL?, minMenus: Int = 1) {
        let failure = shot.flatMap { shoot(pid: pid, status: status, statusItem: statusItem, minMenus: minMenus, out: $0) }
        let missingLabels = missing.map { "\($0.label) (\($0.identifier))" } + (failure.map { [$0] } ?? [])
        steps.append(WalkStep(
            name: name, opened: opened, via: via, missing: missingLabels,
            screenshot: failure == nil ? shot?.lastPathComponent : nil
        ))
        print("step \(name): \(opened && missingLabels.isEmpty ? "ok" : "FAIL") via=\(via)"
            + (missingLabels.isEmpty ? "" : " missing=\(missingLabels.joined(separator: "; "))"))
    }

    if menu.open() {
        let root = menuWindows(pid: pid).map(\.frame)
        let missing = plan.topLevel.missing(from: visibleIdentifiers(under: menu.status, inside: root))
        record("menu", opened: true, via: "status item", missing: missing, shot: outDir.appendingPathComponent("menu.png"))
        closeMenu(menu)
    } else {
        record("menu", opened: false, via: "status item", missing: plan.topLevel, shot: nil)
    }

    for submenu in plan.submenus {
        guard menu.open(), let opener = element(submenu.opener.identifier, under: menu.status) else {
            record(submenu.name, opened: false, via: "none", missing: [submenu.opener], shot: nil)
            closeMenu(menu)
            continue
        }
        let root = menuWindows(pid: pid).map(\.frame)
        guard let via = openSubmenu(opener, pid: pid) else {
            record(submenu.name, opened: false, via: "none", missing: submenu.expectedChildren, shot: nil)
            closeMenu(menu)
            continue
        }
        Thread.sleep(forTimeInterval: 0.2)
        let opened = menuWindows(pid: pid).map(\.frame).filter { !root.contains($0) }
        let missing = submenu.expectedChildren.missing(from: visibleIdentifiers(under: opener, inside: opened))
        record(submenu.name, opened: true, via: via, missing: missing,
               shot: outDir.appendingPathComponent("\(submenu.name).png"), minMenus: root.count + 1)
        closeMenu(menu)
    }

    let report = WalkReport(
        plan: planName, fixture: plan.fixture, steps: steps,
        ok: steps.allSatisfy { $0.opened && $0.missing.isEmpty }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(report).write(to: outDir.appendingPathComponent("menu-walk.json"))
    } catch {
        fail("cannot write report: \(error)")
    }
    print("report: \(outDir.appendingPathComponent("menu-walk.json").path)")
    print("menu-walk: \(report.ok ? "ok" : "FAIL")")
    if !report.ok { exit(1) }
}

// MARK: Menu measure

/// Visible text of a row: its own title plus the static text inside a custom row view, without
/// descending into a submenu's rows.
func rowText(_ element: AXUIElement) -> String {
    var parts: [String] = []
    var stack = [element]
    var visited = 0
    while let node = stack.popLast(), visited < 200 {
        visited += 1
        if node != element, axString(node, "AXRole") == (kAXMenuRole as String) { continue }
        for attribute in ["AXTitle", "AXValue", "AXDescription"] {
            if let text = axString(node, attribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
               !parts.contains(text) {
                parts.append(text)
            }
        }
        stack.append(contentsOf: axChildren(node).reversed())
    }
    return parts.joined(separator: " | ")
}

/// An AX-opened menu sometimes comes up with a row selected (seen on Quit), so two captures of one
/// menu could differ by a highlight. Deselects every root row before the capture.
func clearSelection(in root: AXUIElement) {
    for item in axChildren(root) {
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, "AXSelected" as CFString, &selected) == .success,
              (selected as? Bool) == true
        else {
            continue
        }
        AXUIElementSetAttributeValue(item, "AXSelected" as CFString, kCFBooleanFalse)
        print("selection: cleared \(axString(item, "AXIdentifier") ?? "a row")")
    }
}

func measure(pid: pid_t, fixture: String, outDir: URL, allowSensitiveText: Bool) {
    if let failure = runPreflight().firstFailure {
        fail("measure cannot capture the menu (\(failure.name): \(failure.detail))", code: 3)
    }
    guard AXIsProcessTrusted() else {
        fail("measure cannot open the menu: Accessibility is not granted to this host process", code: 3)
    }
    guard let menu = StatusMenu(pid: pid), let status = statusItemFrame(pid: pid, menu: menu) else {
        fail("status item pdtbar.status not found for pid \(pid)")
    }
    do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) } catch {
        fail("cannot create \(outDir.path): \(error)")
    }
    guard menu.open(), let window = menuWindows(pid: pid).first,
          let root = findElement(in: menu.status, where: { axString($0, "AXRole") == (kAXMenuRole as String) })
    else {
        fail("status menu did not open")
    }
    Thread.sleep(forTimeInterval: 0.3)
    let salt = MeasureReport.newSalt()
    let rows = axChildren(root).compactMap { item -> MeasuredRow? in
        guard let frame = axFrame(item), frame.height > 0 else { return nil }
        var enabled: CFTypeRef?
        AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled)
        return MeasuredRow(
            role: axString(item, "AXRole") ?? "?",
            identifier: axString(item, "AXIdentifier"),
            rawText: rowText(item),
            salt: salt,
            includeText: allowSensitiveText,
            y: Int((frame.minY - window.frame.minY).rounded()),
            height: Int(frame.height.rounded()),
            hasSubmenu: axChildren(item).contains { axString($0, "AXRole") == (kAXMenuRole as String) },
            enabled: (enabled as? Bool) ?? true
        )
    }
    let failure = shoot(pid: pid, status: status, statusItem: menu.statusFrame ?? status, minMenus: 1,
                        out: outDir.appendingPathComponent("menu.png")) { clearSelection(in: root) }
    closeMenu(menu)
    if let failure { fail("menu capture failed: \(failure)") }
    let report = MeasureReport(
        fixture: URL(fileURLWithPath: fixture).lastPathComponent,
        menuWidth: Int(window.frame.width.rounded()), menuHeight: Int(window.frame.height.rounded()),
        sensitiveText: allowSensitiveText, rows: rows
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try encoder.encode(report).write(to: outDir.appendingPathComponent("measure.json"))
    } catch {
        fail("cannot write report: \(error)")
    }
    print("measure: \(rows.count) rows, \(report.menuHeight)pt -> \(outDir.appendingPathComponent("measure.json").path)")
    if report.clampedToScreen {
        print("warning: macOS clamped the menu to the screen and scrolls it; menuHeight \(report.menuHeight)pt is the clamp, the rows need \(report.contentHeight)pt")
    }
}

// MARK: Press

/// Opens the status menu and presses `pdtbar.row.<row>`, found by identifier only. Exits 2 when this
/// build's menu has no such enabled row, so a caller can record that instead of failing.
func press(pid: pid_t, row: String) {
    guard AXIsProcessTrusted() else {
        fail("press cannot open the menu: Accessibility is not granted to this host process", code: 3)
    }
    guard let menu = StatusMenu(pid: pid) else { fail("status item pdtbar.status not found for pid \(pid)") }
    guard menu.open() else { fail("status menu did not open") }
    Thread.sleep(forTimeInterval: 0.3)
    let identifier = "pdtbar.row.\(row)"
    guard let item = element(identifier, under: menu.status) else {
        closeMenu(menu)
        print("pressed: false (\(identifier) not in this menu)")
        exit(2)
    }
    var enabled: CFTypeRef?
    AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled)
    guard (enabled as? Bool) ?? true else {
        closeMenu(menu)
        print("pressed: false (\(identifier) is disabled)")
        exit(2)
    }
    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
    // The item's action runs once the menu stops tracking, which can outlast the AX messaging timeout.
    let closed = waitFor(timeout: 2) { menuWindows(pid: pid).isEmpty }
    guard result == .success || closed else {
        closeMenu(menu)
        fail("AXPress on \(identifier) returned \(result.rawValue) and the menu stayed open")
    }
    if !closed { closeMenu(menu) }
    print("pressed: true (\(identifier))")
}

// MARK: CLI

let usage = """
usage:
  pdtbar-capture preflight
  pdtbar-capture screenshot --pid <pid> --out <file.png> [--closed]
  pdtbar-capture record --pid <pid> --seconds <1-30> --out <file.mov>
  pdtbar-capture walk --pid <pid> --plan <name> --fixture <file.json> --out-dir <dir>
  pdtbar-capture measure --pid <pid> --fixture <name> --out-dir <dir> [--allow-sensitive-text]
  pdtbar-capture press --pid <pid> --row <id>    # presses pdtbar.row.<id>; exit 2 when absent or disabled
"""

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "preflight":
    let (results, firstFailure) = runPreflight()
    for result in results {
        print("\(result.name): \(result.ok ? "ok" : "no") (\(result.detail))")
    }
    print("accessibility: \(accessibilityLine())")
    if let firstFailure {
        print("can-capture: no (\(firstFailure.name): \(firstFailure.detail))")
        exit(3)
    }
    print("can-capture: yes")
case "screenshot":
    guard let pid = option("--pid", in: arguments).flatMap(pid_t.init), let out = option("--out", in: arguments) else {
        fail(usage, code: 64)
    }
    screenshot(pid: pid, out: URL(fileURLWithPath: out), wantMenu: !arguments.contains("--closed"))
case "record":
    guard let pid = option("--pid", in: arguments).flatMap(pid_t.init),
          let seconds = option("--seconds", in: arguments).flatMap(Int.init), (1...30).contains(seconds),
          let out = option("--out", in: arguments)
    else {
        fail(usage, code: 64)
    }
    record(pid: pid, seconds: seconds, out: URL(fileURLWithPath: out))
    await writePoster(movie: URL(fileURLWithPath: out))
case "walk":
    guard let pid = option("--pid", in: arguments).flatMap(pid_t.init),
          let plan = option("--plan", in: arguments),
          let fixture = option("--fixture", in: arguments),
          let outDir = option("--out-dir", in: arguments)
    else {
        fail(usage, code: 64)
    }
    walk(pid: pid, planName: plan, fixture: fixture, outDir: URL(fileURLWithPath: outDir))
case "measure":
    guard let pid = option("--pid", in: arguments).flatMap(pid_t.init),
          let fixture = option("--fixture", in: arguments),
          let outDir = option("--out-dir", in: arguments)
    else {
        fail(usage, code: 64)
    }
    measure(
        pid: pid, fixture: fixture, outDir: URL(fileURLWithPath: outDir),
        allowSensitiveText: arguments.contains("--allow-sensitive-text")
    )
case "press":
    guard let pid = option("--pid", in: arguments).flatMap(pid_t.init), let row = option("--row", in: arguments) else {
        fail(usage, code: 64)
    }
    press(pid: pid, row: row)
default:
    fail(usage, code: 64)
}
