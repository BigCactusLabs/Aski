import ArgumentParser

/// Executes an asynchronous ArgumentParser root without selecting the inherited
/// synchronous `ParsableCommand.main` overload.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public enum AsyncCommandRunner {
    public static func main<Command: AsyncParsableCommand>(_ root: Command.Type) async {
        do {
            var command = try await root.asyncParseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            root.exit(withError: error)
        }
    }
}
