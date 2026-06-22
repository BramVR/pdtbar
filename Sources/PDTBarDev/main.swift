import Foundation
import PDTBarCore

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3,
          ["model", "descriptor"].contains(arguments[0]),
          arguments[1] == "--fixture"
    else {
        throw CommandError.usage
    }

    let fixtureURL = URL(fileURLWithPath: arguments[2])
    let snapshot = try PDTFixtureDataSource.snapshot(from: fixtureURL)
    let model = PressureEngine.buildModel(from: snapshot)
    let output: Data
    if arguments[0] == "model" {
        output = try stableJSONData(model)
    } else {
        output = try stableJSONData(MenuDescriptorRenderer.render(model: model))
    }

    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch CommandError.usage {
    FileHandle.standardError.write(
        Data("usage: pdtbar-dev <model|descriptor> --fixture <path>\n".utf8)
    )
    Foundation.exit(64)
} catch {
    FileHandle.standardError.write(Data("pdtbar-dev: \(error)\n".utf8))
    Foundation.exit(1)
}

private enum CommandError: Error {
    case usage
}
