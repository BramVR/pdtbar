import AppKit
import Foundation
import PDTBarCore

public final class MenuActionDispatcher: NSObject {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @objc public func copyMenuRowAction(_ sender: NSMenuItem) {
        guard let actionTarget = sender.representedObject as? MenuRowActionTarget else {
            return
        }
        copy(actionTarget: actionTarget)
    }

    @discardableResult
    public func copy(actionTarget: MenuRowActionTarget) -> Bool {
        guard let copyText = actionTarget.copyText,
              !copyText.isEmpty
        else {
            return false
        }
        switch actionTarget.kind {
        case .copyHoldingIdentifier, .copyDataHealthDiagnostic:
            break
        case .incomeEvent:
            return false
        }
        pasteboard.clearContents()
        return pasteboard.setString(copyText, forType: .string)
    }
}
