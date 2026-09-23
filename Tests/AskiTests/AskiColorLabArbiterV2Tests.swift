import Foundation
import Testing

@_spi(AskiResearch) import Aski
@testable import AskiColorLab

/// Independent contracts added by ASKI-62. These run the real converter rather
/// than mirroring the v2 implementation. The frozen v1 answer-key decode check
/// is not part of the public tree: the aski56 key file is withheld while the
/// blinded study is pending, and only its aggregates are published.
@Suite struct AskiColorLabArbiterV2Tests {

    @Test func v2KeyRoundTripsBothArmKindsAndPolarityValues() throws {
        let sources = ArbiterTestSupport.sources()
        let plan = Arbiter.FamilyPlan()
        let pairs = try Arbiter.PairPlan.build(
            sources: sources,
            scores: ArbiterTestSupport.scoreTable(sources: sources, plan: plan),
            plan: plan,
            seed: 4242)
        let encoded = try StableJSONForTest.encode(
            Arbiter.KeyFile(seed: 4242, pairs: pairs))
        let text = String(decoding: encoded, as: UTF8.self)
        let decoded = try JSONDecoder().decode(Arbiter.KeyFile.self, from: encoded)

        #expect(decoded.schemaVersion == "2")
        #expect(decoded.protocolVersion == "2")
        #expect(text.contains("\"kind\" : \"selection\""))
        #expect(text.contains("\"kind\" : \"converter\""))
        #expect(text.contains("\"shape_query_polarity\" : \"inverted\""))
        #expect(text.contains("\"shape_query_polarity\" : \"direct\""))
        #expect(try decoded.pairs().map(\.signature) == pairs.map(\.signature))
    }

    @Test func unknownArmKindsNamesAndPolarityValuesFailLoudly() throws {
        let unknownKind = Data(#"{"kind":"future","name":"P"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Arbiter.ArmRef.self, from: unknownKind)
        }

        #expect(Arbiter.ArmRef(name: "future-selector").arm == nil)
        #expect(Arbiter.ArmRef(name: "F", w: 2).arm == nil)
        #expect(
            Arbiter.ArmRef(
                kind: .converter, name: "P", shapeQueryPolarity: "sideways"
            ).arm == nil)
        #expect(
            Arbiter.ArmRef(
                kind: .converter, name: "P", topK: 12,
                shapeQueryPolarity: "inverted"
            ).arm == nil)
        #expect(
            Arbiter.ArmRef(
                kind: .converter, name: "future-converter",
                shapeQueryPolarity: "inverted"
            ).arm == nil)
    }

    @Test func frozenV2KeyRejectsMissingKindsAndVersionOrBudgetDrift() throws {
        try Self.expectInvalidFrozenV2 { root in
            var entries = try #require(root["entries"] as? [[String: Any]])
            var first = entries[0]
            var arm = try #require(first["arm_a"] as? [String: Any])
            arm.removeValue(forKey: "kind")
            first["arm_a"] = arm
            entries[0] = first
            root["entries"] = entries
        }
        try Self.expectInvalidFrozenV2 { root in
            root["protocol_version"] = "1"
        }
        try Self.expectInvalidFrozenV2 { root in
            var counts = try #require(root["family_counts"] as? [String: Int])
            counts["V"] = 5
            root["family_counts"] = counts
        }
    }

    @Test func frozenV2KeyRejectsDuplicateIDsAndBrokenRepeatReferences() throws {
        try Self.expectInvalidFrozenV2 { root in
            var entries = try #require(root["entries"] as? [[String: Any]])
            entries[1]["pair_id"] = entries[0]["pair_id"]
            root["entries"] = entries
        }
        try Self.expectInvalidFrozenV2 { root in
            var entries = try #require(root["entries"] as? [[String: Any]])
            let repeatIndex = try #require(
                entries.firstIndex { $0["family"] as? String == "R" })
            entries[repeatIndex]["repeat_of"] = "pair-does-not-exist"
            root["entries"] = entries
        }
    }

    @Test func scoreArtifactsReportTheInputKeysProtocolVersion() throws {
        let pairs = try Self.pairs()
        let report = try Arbiter.Score.score(
            .init(
                key: .init(seed: 4242, pairs: pairs),
                humanAnswers: [:],
                judgements: []))
        let yaml = Arbiter.Score.resultYAML(
            report: report,
            date: "2026-09-04",
            gitSHA: "abc1234",
            seed: 4242,
            command: "AskiColorLab arbiter score",
            outputs: ["readout.md"],
            protocolVersion: "1")
        let markdown = Arbiter.Score.readout(report, protocolVersion: "1")

        #expect(yaml.contains("(v1, committed before any vote)"))
        #expect(!yaml.contains("(v2, committed before any vote)"))
        #expect(yaml.contains("2026-08-25-aski56-arbiter-protocol.md"))
        #expect(!yaml.contains("2026-09-04-aski62-arbiter-v2-protocol.md"))
        #expect(markdown.contains("(v1, frozen)"))
    }

    @Test func converterArmsMatchIndependentRealConverterRuns() {
        let fixture = Self.fixture()
        let inverted = Arbiter.Census.converterGrid(
            fixture: fixture, characterSet: .blocks, arm: .productionInverted,
            columns: 24, oversample: 2)
        let defaultGrid = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            colorSpace: .sRGB,
            oversample: 2
        ).convert(fixture.image, columns: 24)

        var options = RenderingOptions.default
        options.shapeQueryPolarity = .direct
        let direct = Arbiter.Census.converterGrid(
            fixture: fixture, characterSet: .blocks, arm: .productionDirect,
            columns: 24, oversample: 2)
        let explicitDirect = ASCIIConverter(
            characterSet: StandardCharacterSet.blocks,
            palette: BuiltInPalette.monochrome,
            options: options,
            colorSpace: .sRGB,
            oversample: 2
        ).convert(fixture.image, columns: 24)

        Self.expectEqual(inverted, defaultGrid)
        Self.expectEqual(direct, explicitDirect)
    }

    @Test func censusKeepsArmGridsSeparateAndConvertsEachConverterArmOnce() throws {
        let inverted = Arbiter.ArmRef(Arbiter.ConverterArm.productionInverted)
        let direct = Arbiter.ArmRef(Arbiter.ConverterArm.productionDirect)
        let floor = Arbiter.ArmRef(SelectionCeiling.Arm.floor)
        let result = try Arbiter.Census.run(
            fixture: Self.fixture(),
            charsetName: "blocks",
            arms: [
                .converter(.productionInverted),
                .converter(.productionDirect),
                .selection(.floor),
            ],
            columns: 24,
            oversample: 2,
            footprint: 24)

        #expect(result.converterConversionCounts == [inverted: 1, direct: 1])
        #expect(Set(result.grids.keys) == Set([inverted, direct, floor]))
        let invertedGrid = try #require(result.grids[inverted])
        let directGrid = try #require(result.grids[direct])
        let floorGrid = try #require(result.grids[floor])

        #expect(
            invertedGrid.cells.flatMap { $0 }.map(\.character)
                != directGrid.cells.flatMap { $0 }.map(\.character))
        for (baseline, selection) in zip(
            invertedGrid.cells.flatMap({ $0 }), floorGrid.cells.flatMap({ $0 }))
        {
            #expect(baseline.displayColor.x.bitPattern == selection.displayColor.x.bitPattern)
            #expect(baseline.displayColor.y.bitPattern == selection.displayColor.y.bitPattern)
            #expect(baseline.displayColor.z.bitPattern == selection.displayColor.z.bitPattern)
            #expect(baseline.alpha.bitPattern == selection.alpha.bitPattern)
            #expect(baseline.brightness.bitPattern == selection.brightness.bitPattern)
            #expect(baseline.coverage.bitPattern == selection.coverage.bitPattern)
        }
    }

    private static func fixture() -> ResidualFixture {
        let width = 96
        let height = 96
        var gray = [UInt8](repeating: 12, count: width * height)
        for y in 0..<height {
            for x in 0..<width where x % 16 < 5 && y % 24 >= 6 {
                gray[y * width + x] = 235
            }
        }
        return ResidualFixture.fromGrayBytes(
            id: "arbiter-v2-polarity", width: width, height: height,
            pool: .synthetic, gray: gray)
    }

    private static func pairs() throws -> [Arbiter.Pair] {
        let sources = ArbiterTestSupport.sources()
        let plan = Arbiter.FamilyPlan()
        return try Arbiter.PairPlan.build(
            sources: sources,
            scores: ArbiterTestSupport.scoreTable(sources: sources, plan: plan),
            plan: plan,
            seed: 4242)
    }

    private static func expectInvalidFrozenV2(
        _ mutate: (inout [String: Any]) throws -> Void
    ) throws {
        let data = try StableJSONForTest.encode(
            Arbiter.KeyFile(seed: 4242, pairs: pairs()))
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutate(&root)
        let mutated = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let key = try JSONDecoder().decode(Arbiter.KeyFile.self, from: mutated)
        #expect(throws: ArbiterError.self) {
            try key.pairs()
        }
    }

    private static func expectEqual(_ lhs: ASCIIGrid, _ rhs: ASCIIGrid) {
        #expect(lhs.rows == rhs.rows)
        #expect(lhs.columns == rhs.columns)
        for (left, right) in zip(lhs.cells.flatMap({ $0 }), rhs.cells.flatMap({ $0 })) {
            #expect(left.character == right.character)
            #expect(left.displayColor.x.bitPattern == right.displayColor.x.bitPattern)
            #expect(left.displayColor.y.bitPattern == right.displayColor.y.bitPattern)
            #expect(left.displayColor.z.bitPattern == right.displayColor.z.bitPattern)
            #expect(left.alpha.bitPattern == right.alpha.bitPattern)
            #expect(left.brightness.bitPattern == right.brightness.bitPattern)
            #expect(left.coverage.bitPattern == right.coverage.bitPattern)
        }
    }
}
