import AskiToolSupport
import Foundation
import Testing

@testable import AskiColorLab

/// Guards prerequisite 4: the machine-readable artifact the frozen ASKI-28/30
/// rule is applied to.
///
/// The ASTSK-31 discipline is that the verdict is read mechanically from a file,
/// not argued from a printed table — so this file's shape is load-bearing. A
/// missing corpus column makes every figure unquotable under the audit's standing
/// rule 4; a missing arm/`w`/`topK` column makes the §4 calibration step
/// ("freeze `w*` and `topK*` into the CSV before the held-out run") impossible;
/// a missing git SHA breaks provenance.
@Suite struct AskiColorLabSelectionCeilingCSVTests {

    private static func row(
        arm: String, w: Float? = nil, topK: Int? = nil,
        corpus: String = "nasa-steerable-v1", charset: String = "blocks",
        means: [SelectionCeiling.Oracle: Double] = [
            .mae: 0.25, .rmse: 0.26, .ssim: 0.30, .gmsd: 0.20, .haarPSI: 0.38,
        ],
        seconds: Double = 1.5,
        polarity: String = "inverted"
    ) -> SelectionCeiling.ArmRow {
        SelectionCeiling.ArmRow(
            corpus: corpus, charset: charset, arm: arm, w: w, topK: topK,
            columns: 80, oversample: 2, footprint: 24, stride: 1, cells: 8640, glyphs: 8,
            means: means, selectionWallSeconds: seconds, gitSHA: "abc1234",
            shapeQueryPolarity: polarity)
    }

    /// The column contract, pinned in order. The rule reads these by name.
    @Test func headerCarriesEveryColumnTheFrozenRuleReads() {
        let header = SelectionCeiling.csv([]).split(separator: "\n").first.map(String.init)
        #expect(
            header
                == "corpus,charset,arm,w,topK,columns,oversample,footprint,stride,cells,glyphs,"
                + "mae,rmse,ssim,gmsd,haarpsi,selectionWallSeconds,gitSHA,shapeQueryPolarity")
    }

    /// ASKI-60: the shape-query polarity changes the converter, so a `direct`
    /// census must be distinguishable from the default one by its rows alone.
    @Test func rowsRecordTheShapeQueryPolarityTheyWereMeasuredUnder() {
        let csv = SelectionCeiling.csv([
            Self.row(arm: "P"), Self.row(arm: "P", polarity: "direct"),
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines[1].hasSuffix(",abc1234,inverted"))
        #expect(lines[2].hasSuffix(",abc1234,direct"))
    }

    /// One row per (corpus, charset, arm, w, topK), with the parameter columns
    /// empty for the arms that take no parameter — never `0`, which would read
    /// as a swept point at `w = 0` (an anchor the rule actually uses).
    @Test func parameterColumnsAreEmptyRatherThanZeroForUnparameterizedArms() throws {
        let csv = SelectionCeiling.csv([Self.row(arm: "P"), Self.row(arm: "T", w: 0)])
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 3, "expected a header and two rows")

        let production = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(production[2] == "P")
        #expect(production[3] == "", "arm P reported a w value")
        #expect(production[4] == "", "arm P reported a topK value")

        let toneWeighted = lines[2].split(separator: ",", omittingEmptySubsequences: false)
        #expect(toneWeighted[3] == "0", "the w=0 anchor was rendered as empty")
    }

    /// Provenance and geometry travel with every row, so a row is quotable on
    /// its own — the audit's standing rule 4 ("name the corpus") applies to a
    /// CSV cell exactly as it applies to a sentence.
    @Test func everyRowCarriesCorpusGeometryAndProvenance() throws {
        let csv = SelectionCeiling.csv([Self.row(arm: "K", topK: 95, corpus: "nasa-structure-v1")])
        let fields = try #require(csv.split(separator: "\n").last)
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(fields[0] == "nasa-structure-v1")
        #expect(fields[1] == "blocks")
        #expect(fields[4] == "95")
        #expect(fields[5] == "80")  // columns
        #expect(fields[6] == "2")  // oversample
        #expect(fields[7] == "24")  // footprint
        #expect(fields[8] == "1")  // stride
        #expect(fields[9] == "8640")  // cells
        #expect(fields[10] == "8")  // glyphs
        #expect(fields[17] == "abc1234")  // gitSHA
        #expect(fields.last == "inverted")  // shapeQueryPolarity (ASKI-60)
    }

    /// The five oracle means land in their own named columns, in header order.
    /// The rule reads `mae` and demotes on `rmse`/`ssim`; putting a comparator
    /// in a gating column would silently change the verdict.
    @Test func oracleMeansLandInTheirNamedColumns() throws {
        let csv = SelectionCeiling.csv([
            Self.row(
                arm: "F",
                means: [.mae: 0.1, .rmse: 0.2, .ssim: 0.3, .gmsd: 0.4, .haarPSI: 0.5])
        ])
        let fields = try #require(csv.split(separator: "\n").last)
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(Double(fields[11]) == 0.1, "mae column")
        #expect(Double(fields[12]) == 0.2, "rmse column")
        #expect(Double(fields[13]) == 0.3, "ssim column")
        #expect(Double(fields[14]) == 0.4, "gmsd column")
        #expect(Double(fields[15]) == 0.5, "haarpsi column")
    }

    /// A missing oracle mean must be an empty cell, not a zero — zero is a
    /// legitimate (and excellent) MAE, and the tie/zero policy in §5.1 already
    /// gives `nan` a defined meaning. Silently inventing 0.0 would read as the
    /// strongest possible result.
    @Test func aMissingOracleMeanIsEmptyNotZero() throws {
        let csv = SelectionCeiling.csv([Self.row(arm: "F", means: [.mae: 0.1])])
        let fields = try #require(csv.split(separator: "\n").last)
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(fields[11] == "0.1")
        #expect(fields[12] == "", "a missing rmse mean was rendered as a number")
    }

    /// Selection wall seconds are per-row (§2.5 cost, §5.2's 2.0x cost cap).
    /// Median-of-3 is orchestrated across runs, so the harness emits one number
    /// per run and must not round it into uselessness.
    @Test func selectionWallSecondsSurviveAtSubMillisecondResolution() throws {
        let csv = SelectionCeiling.csv([Self.row(arm: "K", topK: 12, seconds: 0.0421)])
        let fields = try #require(csv.split(separator: "\n").last)
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(Double(fields[16]) == 0.0421)
    }

    /// The rule is applied to this file by machine, so it has to parse as CSV.
    /// Charsets and arm labels are ASCII here, but a git SHA override or a
    /// corpus directory name is user-supplied and could carry a comma.
    @Test func fieldsContainingSeparatorsAreQuoted() throws {
        let csv = SelectionCeiling.csv([Self.row(arm: "P", corpus: "odd,name")])
        let fields = try #require(csv.split(separator: "\n").last)
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(fields[0] == "\"odd", "an embedded comma was not quoted")
        #expect(csv.contains("\"odd,name\""))
    }
}
