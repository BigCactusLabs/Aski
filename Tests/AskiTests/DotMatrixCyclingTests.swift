import Foundation
import ImageIO
import Testing
@testable import Aski

@Suite struct DotMatrixCyclingTests {
    @Test func rankedCandidatesKeepEveryBasePickAndFollowDensityOrder() {
        let image = TestImages.structuredPortraitProxy(width: 240, height: 320)
        let characterSet = StandardCharacterSet.standard
        let converter = ASCIIConverter(
            characterSet: characterSet,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix
        )
        let ranked = converter.convertWithRankedCandidates(image, columns: 24, candidateStride: 4)
        let converted = converter.convert(image, columns: 24)
        let animated = converter.animate(
            image, columns: 24,
            options: AnimationOptions(duration: 2, cycling: CyclingOptions(k: 4, speed: 1, intensity: 1, randomness: 0))
        )

        #expect(ranked.grid.cells == converted.cells)
        #expect(animated.baseGrid.cells == converted.cells)
        #expect(ranked.candidateCounts.allSatisfy { $0 == 4 })
        for row in 0..<ranked.grid.rows {
            for column in 0..<ranked.grid.columns {
                let cellIndex = row * ranked.grid.columns + column
                let indices = (0..<4).map { Int(ranked.candidates[cellIndex * 4 + $0]) }
                #expect(Set(indices).count == 4)
                #expect(characterSet.characters[indices[0]] == converted.cells[row][column].character)
                let baseDensity = characterSet.brightnessValues[indices[0]]
                let expected = characterSet.characters.indices
                    .filter { $0 != indices[0] }
                    .sorted {
                        let left = abs(characterSet.brightnessValues[$0] - baseDensity)
                        let right = abs(characterSet.brightnessValues[$1] - baseDensity)
                        return left == right ? $0 < $1 : left < right
                    }
                #expect(Array(indices.dropFirst()) == Array(expected.prefix(3)))
            }
        }

        let first = animated.grid(at: 0).cells
        let later = animated.grid(at: 0.34).cells
        let changed = zip(first.joined(), later.joined()).filter { $0.0.character != $0.1.character }.count
        #expect(changed > 0)
    }

    @Test func nasaFixtureDensityAndDefaultFrameChangeRates() throws {
        for (fixture, path) in Self.fixtures {
            let image = try Self.loadImage(path)
            for (name, characterSet, meanBound) in Self.characterSets {
                let converter = ASCIIConverter(
                    characterSet: characterSet,
                    palette: BuiltInPalette.fullColor,
                    algorithm: .dotMatrix
                )
                let ranked = converter.convertWithRankedCandidates(
                    image, columns: 80, candidateStride: CyclingOptions.default.k
                )
                var total = 0.0
                var maximum = 0.0
                var samples = 0
                for cell in 0..<ranked.candidateCounts.count {
                    let base = Int(ranked.candidates[cell * ranked.candidateStride])
                    for slot in 1..<Int(ranked.candidateCounts[cell]) {
                        let candidate = Int(ranked.candidates[cell * ranked.candidateStride + slot])
                        let difference = Double(
                            abs(characterSet.brightnessValues[candidate] - characterSet.brightnessValues[base])
                        )
                        total += difference
                        maximum = max(maximum, difference)
                        samples += 1
                    }
                }
                let mean = total / Double(samples)
                print("ASKI81 density \(fixture) \(name): mean=\(mean) max=\(maximum) samples=\(samples)")
                // Each bound rounds the larger measured fixture mean up to
                // the next hundredth in normalized brightness units.
                #expect(mean <= meanBound)
            }

            for algorithm in [ASCIIAlgorithm.dotMatrix, .logPolar] {
                let converter = ASCIIConverter(
                    characterSet: StandardCharacterSet.standard,
                    palette: BuiltInPalette.fullColor,
                    algorithm: algorithm
                )
                let frames = converter.animate(
                    image, columns: 80, options: AnimationOptions(duration: 2)
                ).materialize(frameRate: 8)
                var changed = 0
                var comparisons = 0
                for index in 1..<frames.count {
                    for (previous, current) in zip(frames[index - 1].cells.joined(), frames[index].cells.joined()) {
                        if previous.character != current.character { changed += 1 }
                        comparisons += 1
                    }
                }
                let rate = Double(changed) / Double(comparisons)
                print("ASKI81 frames \(fixture) \(algorithm): changed=\(changed) comparisons=\(comparisons) rate=\(rate)")
                if algorithm == .dotMatrix { #expect(rate > 0) }
            }
        }
    }

    @Test func candidateCountStopsAtGlyphCountAndPaddingKeepsWinner() {
        let characterSet = StandardCharacterSet.minimal
        let converter = ASCIIConverter(
            characterSet: characterSet,
            palette: BuiltInPalette.fullColor,
            algorithm: .dotMatrix
        )
        let stride = characterSet.characters.count + 2
        let ranked = converter.convertWithRankedCandidates(
            TestImages.horizontalGradient(width: 80, height: 40),
            columns: 8,
            candidateStride: stride
        )
        for cell in ranked.candidateCounts.indices {
            #expect(Int(ranked.candidateCounts[cell]) == characterSet.characters.count)
            let indices = (0..<stride).map { ranked.candidates[cell * stride + $0] }
            #expect(Set(indices.prefix(characterSet.characters.count)).count == characterSet.characters.count)
            #expect(indices[stride - 2] == indices[0])
            #expect(indices[stride - 1] == indices[0])
        }
    }

    private static let fixtures: [(String, String)] = [
        ("vavilov-crater", "docs/Research/Corpus/nasa-steerable-v1/assets/vavilov-crater.png"),
        ("cernan-portrait", "docs/Research/Corpus/nasa-occupancy-v1/assets/cernan-portrait.jpg"),
    ]

    private static let characterSets: [(String, StandardCharacterSet, Double)] = [
        ("standard", .standard, 0.04), ("minimal", .minimal, 0.17), ("braille", .braille, 0.01),
    ]

    private static func loadImage(_ path: String) throws -> CGImage {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try #require(CGImageSourceCreateWithURL(root.appendingPathComponent(path) as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}
