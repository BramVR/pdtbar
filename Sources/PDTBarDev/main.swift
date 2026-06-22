import Foundation
import PDTBarCore

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let output: Data

    if arguments.count == 3,
       ["model", "descriptor"].contains(arguments[0]),
       arguments[1] == "--fixture"
    {
        let fixtureURL = URL(fileURLWithPath: arguments[2])
        let snapshot = try PDTFixtureDataSource.snapshot(from: fixtureURL)
        let model = PressureEngine.buildModel(from: snapshot)
        if arguments[0] == "model" {
            output = try stableJSONData(model)
        } else {
            output = try stableJSONData(MenuDescriptorRenderer.render(model: model))
        }
    } else if arguments.count == 5,
              arguments[0] == "run",
              arguments[1] == "--fixture",
              arguments[3] == "--snapshot-dir"
    {
        output = try stableJSONData(
            PressureRunner.run(
                fixture: URL(fileURLWithPath: arguments[2]),
                snapshotDirectory: URL(fileURLWithPath: arguments[4])
            )
        )
    } else {
        throw CommandError.usage
    }

    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch CommandError.usage {
    FileHandle.standardError.write(
        Data("usage: pdtbar-dev <model|descriptor> --fixture <path>\n       pdtbar-dev run --fixture <path> --snapshot-dir <path>\n".utf8)
    )
    Foundation.exit(64)
} catch {
    FileHandle.standardError.write(Data("pdtbar-dev: \(error)\n".utf8))
    Foundation.exit(1)
}

private enum CommandError: Error {
    case usage
}
