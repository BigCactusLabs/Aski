import Foundation

enum BuildResearchIndexCLI {
    enum Mode: Equatable {
        case regenerate
        case check
        case help
    }

    enum ArgumentError: Error, Equatable, CustomStringConvertible {
        case unexpectedArguments([String])

        var description: String {
            switch self {
            case .unexpectedArguments(let args):
                "unexpected arguments: \(args.joined(separator: " "))"
            }
        }
    }

    static let usage = """
        Usage: BuildResearchIndex [--check | --help]
          (no args)   Rewrite docs/Research/README.md and docs/Research/index.json
          --check     Validate front-matter, manifests, and generated index drift
          -h, --help  Show this help message
        """

    static func parseArguments(_ arguments: [String]) throws -> Mode {
        switch arguments {
        case []:
            return .regenerate
        case ["--check"]:
            return .check
        case ["--help"], ["-h"]:
            return .help
        default:
            throw ArgumentError.unexpectedArguments(arguments)
        }
    }
}
