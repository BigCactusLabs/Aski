import Foundation

/// Deterministic JSON for command-line contracts: sorted keys, stable pretty
/// printing, unescaped slashes, and exactly one trailing newline.
public enum StableJSON {
    public static func data<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try data(for: value).write(to: url, options: .atomic)
    }
}
