import Aski
import ArgumentParser

/// CLI-selectable built-in character set. `CaseIterable` + `ExpressibleByArgument`
/// makes SAP auto-list the allowed values in `--help` and auto-reject unknowns.
public enum Charset: String, CaseIterable, ExpressibleByArgument, Sendable {
    case standard, minimal, blocks, dots, lines, diagonal, cross, diamond, mixed, braille

    public var characterSet: StandardCharacterSet {
        switch self {
        case .standard: .standard
        case .minimal: .minimal
        case .blocks: .blocks
        case .dots: .dots
        case .lines: .lines
        case .diagonal: .diagonal
        case .cross: .cross
        case .diamond: .diamond
        case .mixed: .mixed
        case .braille: .braille
        }
    }
}
