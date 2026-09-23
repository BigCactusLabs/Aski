import Foundation

/// A parsed YAML front-matter value: either a scalar string or a list of strings.
/// The parser supports only the constrained subset the research-note schema uses.
enum FrontMatterValue: Equatable {
    case scalar(String)
    case list([String])
}

struct FrontMatterError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Constrained YAML front-matter parser. Handles `key: value` scalars (bare,
/// double-quoted, or single-quoted), inline lists `[a, b]`, and block lists
/// (`- item` lines under a key). Anything outside that grammar — nested maps,
/// anchors, multiline `|`/`>` scalars — is rejected loudly rather than silently
/// misparsed, so a malformed note fails the `swift test` gate instead of
/// producing a wrong index.
enum FrontMatterParser {
    /// Parse the leading `---`-delimited front-matter block of a document.
    static func parse(_ text: String) throws -> [String: FrontMatterValue] {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw FrontMatterError(message: "missing front-matter: file must begin with a '---' line")
        }
        var closing: Int?
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            closing = index
            break
        }
        guard let end = closing else {
            throw FrontMatterError(message: "unterminated front-matter: no closing '---' line")
        }

        var result: [String: FrontMatterValue] = [:]
        var index = 1
        while index < end {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                throw FrontMatterError(message: "unexpected list item outside a key: '\(trimmed)'")
            }
            guard let colon = raw.firstIndex(of: ":") else {
                throw FrontMatterError(message: "unparseable front-matter line: '\(raw)'")
            }
            let key = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else {
                throw FrontMatterError(message: "invalid front-matter key: '\(key)'")
            }
            guard result[key] == nil else {
                throw FrontMatterError(message: "duplicate front-matter key: '\(key)'")
            }
            let rest = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if rest.isEmpty {
                // Block list: consume following indented `- item` lines.
                var items: [String] = []
                var lookahead = index + 1
                while lookahead < end {
                    let itemTrimmed = lines[lookahead].trimmingCharacters(in: .whitespaces)
                    if itemTrimmed.isEmpty || !itemTrimmed.hasPrefix("- ") { break }
                    items.append(try unquote(String(itemTrimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                    lookahead += 1
                }
                guard !items.isEmpty else {
                    throw FrontMatterError(message: "key '\(key)' has no value (expected a scalar or a block list)")
                }
                result[key] = .list(items)
                index = lookahead
            } else if rest.hasPrefix("[") {
                result[key] = .list(try parseInlineList(rest, key: key))
                index += 1
            } else {
                result[key] = .scalar(try unquote(rest))
                index += 1
            }
        }
        return result
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func parseInlineList(_ raw: String, key: String) throws -> [String] {
        guard raw.hasPrefix("["), raw.hasSuffix("]") else {
            throw FrontMatterError(message: "malformed inline list for key '\(key)': '\(raw)'")
        }
        let inner = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return [] }
        return try inner.components(separatedBy: ",").map {
            try unquote($0.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func unquote(_ value: String) throws -> String {
        if value == "|" || value == ">" || value == "|-" || value == ">-" {
            throw FrontMatterError(message: "multiline scalars are unsupported: '\(value)'")
        }
        if value.count >= 2 {
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                return try decodeDoubleQuoted(String(value.dropFirst().dropLast()))
            }
            if value.hasPrefix("'") && value.hasSuffix("'") { return String(value.dropFirst().dropLast()) }
        }
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            throw FrontMatterError(message: "unterminated quoted string: \(value)")
        }
        return value
    }

    private static func decodeDoubleQuoted(_ value: String) throws -> String {
        var decoded = ""
        var isEscaping = false

        for character in value {
            if isEscaping {
                switch character {
                case "\"":
                    decoded.append("\"")
                case "\\":
                    decoded.append("\\")
                case "n":
                    decoded.append("\n")
                case "r":
                    decoded.append("\r")
                case "t":
                    decoded.append("\t")
                default:
                    throw FrontMatterError(message: "unsupported escape sequence: \\\(character)")
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                decoded.append(character)
            }
        }

        if isEscaping {
            throw FrontMatterError(message: "unterminated escape sequence in quoted string")
        }
        return decoded
    }
}

/// The typed, structurally-validated front-matter for a research note.
struct FrontMatter {
    var title: String
    var slug: String
    var date: String
    var status: String
    var subsystem: [String]
    var summary: String
    var relatedSpecs: [String]
    var nextAction: String?
    var datasets: [String]
    var runners: [String]
    var results: [String]

    static let allowedKeys: Set<String> = [
        "title", "slug", "date", "status", "subsystem", "summary",
        "related_specs", "next_action", "datasets", "runners", "results",
    ]

    /// Project a parsed dictionary into the typed schema. Throws on unknown keys,
    /// missing/empty required fields, or scalar/list type mismatches.
    static func from(_ dict: [String: FrontMatterValue]) throws -> FrontMatter {
        for key in dict.keys where !allowedKeys.contains(key) {
            throw FrontMatterError(message: "unknown front-matter key: '\(key)'")
        }

        func scalar(_ key: String, required: Bool) throws -> String? {
            guard let value = dict[key] else {
                if required { throw FrontMatterError(message: "missing required field: '\(key)'") }
                return nil
            }
            guard case .scalar(let string) = value else {
                throw FrontMatterError(message: "field '\(key)' must be a scalar, not a list")
            }
            if required && string.trimmingCharacters(in: .whitespaces).isEmpty {
                throw FrontMatterError(message: "required field '\(key)' is empty")
            }
            return string
        }

        func list(_ key: String, required: Bool) throws -> [String] {
            guard let value = dict[key] else {
                if required { throw FrontMatterError(message: "missing required field: '\(key)'") }
                return []
            }
            guard case .list(let items) = value else {
                throw FrontMatterError(message: "field '\(key)' must be a list")
            }
            if required && items.isEmpty {
                throw FrontMatterError(message: "required list '\(key)' is empty")
            }
            return items
        }

        return FrontMatter(
            title: try scalar("title", required: true)!,
            slug: try scalar("slug", required: true)!,
            date: try scalar("date", required: true)!,
            status: try scalar("status", required: true)!,
            subsystem: try list("subsystem", required: true),
            summary: try scalar("summary", required: true)!,
            relatedSpecs: try list("related_specs", required: false),
            nextAction: try scalar("next_action", required: false),
            datasets: try list("datasets", required: false),
            runners: try list("runners", required: false),
            results: try list("results", required: false)
        )
    }
}
