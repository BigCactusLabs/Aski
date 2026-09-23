import Foundation
import Testing

@testable import AskiColorLab

/// Guards ASKI-56 §2.2, the VLM leg.
///
/// The leg's only defensible claim is the both-orders decide rule: a pair counts
/// for a side only when the majority under BOTH presentation orders agrees, so a
/// judge that is really answering "pick the second image" produces a tie rather
/// than a verdict. That rule, the invalid handling, and the retry-once policy are
/// what separate this from a coin flip, so they are pinned here.
///
/// No network and no `codex` process is involved: the runner is injected.
@Suite struct AskiColorLabArbiterJudgeTests {

    /// A canned in-process runner. Returns the next scripted reply per call and
    /// records what it was asked.
    private final class ScriptedRunner: ArbiterJudgeRunner, @unchecked Sendable {
        private var replies: [String]
        private(set) var calls: [(reference: URL, first: URL, second: URL, allReadable: Bool)] = []
        init(_ replies: [String]) { self.replies = replies }
        func judge(reference: URL, first: URL, second: URL, prompt: String) throws -> String {
            // Existence is recorded HERE, while the call is in flight: the
            // neutral staging directory is transient by design and is cleaned up
            // before `judgePair` returns.
            let readable = [reference, first, second].allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            }
            calls.append((reference, first, second, readable))
            return replies.isEmpty ? "" : replies.removeFirst()
        }
    }

    private static func urls() -> (URL, URL, URL) {
        (
            URL(fileURLWithPath: "/tmp/pair-001-ref.png"),
            URL(fileURLWithPath: "/tmp/pair-001-left.png"),
            URL(fileURLWithPath: "/tmp/pair-001-right.png")
        )
    }

    // MARK: - Parsing

    /// The LAST `VERDICT:` line wins — the frozen prompt asks the judge to think
    /// first, and reasoning text routinely quotes the target format mid-stream.
    @Test func parsingTakesTheLastVerdictLine() {
        let text = """
            I will end with VERDICT: FIRST or VERDICT: SECOND.
            Structure favors the second rendering; tone is a wash.
            VERDICT: SECOND
            """
        #expect(Arbiter.Judge.parseVerdict(text) == .second)
        #expect(Arbiter.Judge.parseVerdict("VERDICT: FIRST\n") == .first)
        #expect(Arbiter.Judge.parseVerdict("verdict: first") == nil, "parsing must be exact")
        #expect(Arbiter.Judge.parseVerdict("no verdict here") == nil)
        #expect(Arbiter.Judge.parseVerdict("VERDICT: TIE") == nil)
    }

    // MARK: - Retry-once

    /// An unparseable reply is retried exactly once, then recorded `invalid`.
    @Test func anUnparseableReplyIsRetriedOnceThenRecordedInvalid() throws {
        let (reference, left, right) = Self.urls()
        let runner = ScriptedRunner(["mumbling", "VERDICT: FIRST"])
        let recovered = try Arbiter.Judge.call(
            runner: runner, reference: reference, first: left, second: right, prompt: "p")
        #expect(recovered.verdict == .first)
        #expect(recovered.retried)
        #expect(runner.calls.count == 2)

        let stubborn = ScriptedRunner(["mumbling", "still mumbling", "VERDICT: FIRST"])
        let failed = try Arbiter.Judge.call(
            runner: stubborn, reference: reference, first: left, second: right, prompt: "p")
        #expect(failed.verdict == .invalid)
        #expect(stubborn.calls.count == 2, "the retry budget is exactly one")
    }

    // MARK: - Aggregation

    private static func calls(
        ab: [Arbiter.Judge.RawVerdict], ba: [Arbiter.Judge.RawVerdict]
    ) -> [Arbiter.Judge.Call] {
        ab.enumerated().map {
            Arbiter.Judge.Call(order: .leftFirst, sample: $0.offset, verdict: $0.element, retried: false)
        }
            + ba.enumerated().map {
                Arbiter.Judge.Call(
                    order: .rightFirst, sample: $0.offset, verdict: $0.element, retried: false)
            }
    }

    /// Both orders agree on LEFT: order `leftFirst` says FIRST, order
    /// `rightFirst` says SECOND. That is the only shape that decides a side.
    @Test func bothOrderMajoritiesAgreeingDecidesTheSide() {
        let decided = Arbiter.Judge.aggregate(
            pairID: "pair-001",
            calls: Self.calls(
                ab: [.first, .first, .second],
                ba: [.second, .second, .second]))
        #expect(decided.decision == .left)
        #expect(decided.orderMajority(.leftFirst) == .left)
        #expect(decided.orderMajority(.rightFirst) == .left)

        let right = Arbiter.Judge.aggregate(
            pairID: "pair-002",
            calls: Self.calls(
                ab: [.second, .second, .second],
                ba: [.first, .first, .first]))
        #expect(right.decision == .right)
    }

    /// Order disagreement is a TIE, never a majority-of-six. A judge with a
    /// position bias answers "first" under both orders; counting all six votes
    /// would turn that bias into a 6-0 verdict for whichever side happened to be
    /// presented first more often.
    @Test func orderDisagreementIsATieNotAPooledMajority() {
        let judgement = Arbiter.Judge.aggregate(
            pairID: "pair-003",
            calls: Self.calls(
                ab: [.first, .first, .first],
                ba: [.first, .first, .first]))
        #expect(judgement.decision == .tie)
        #expect(judgement.orderMajority(.leftFirst) == .left)
        #expect(judgement.orderMajority(.rightFirst) == .right)
    }

    /// Invalid calls count toward neither side. Two valid votes still carry
    /// their order; an order with no valid vote has no majority, so the pair
    /// ties.
    @Test func invalidCallsCountTowardNeitherSide() {
        let partial = Arbiter.Judge.aggregate(
            pairID: "pair-004",
            calls: Self.calls(
                ab: [.invalid, .first, .invalid],
                ba: [.second, .invalid, .invalid]))
        #expect(partial.decision == .left)

        let empty = Arbiter.Judge.aggregate(
            pairID: "pair-005",
            calls: Self.calls(
                ab: [.invalid, .invalid, .invalid],
                ba: [.second, .second, .second]))
        #expect(empty.orderMajority(.leftFirst) == nil)
        #expect(empty.decision == .tie)

        // A dead split inside one order is no majority either.
        let split = Arbiter.Judge.aggregate(
            pairID: "pair-006",
            calls: Self.calls(
                ab: [.first, .second, .invalid],
                ba: [.second, .second, .second]))
        #expect(split.orderMajority(.leftFirst) == nil)
        #expect(split.decision == .tie)
    }

    /// The raw split of all six verdicts is published per pair — §2.2 makes it
    /// the reproducibility substitute for a temperature control nobody can set.
    @Test func rawVoteSplitIsRecordedForEveryPair() {
        let judgement = Arbiter.Judge.aggregate(
            pairID: "pair-007",
            calls: Self.calls(
                ab: [.first, .invalid, .second],
                ba: [.second, .second, .first]))
        #expect(judgement.calls.count == 6)
        #expect(judgement.voteSplit.left == 3)
        #expect(judgement.voteSplit.right == 2)
        #expect(judgement.voteSplit.invalid == 1)
    }

    // MARK: - Injected transport

    /// `--runner` really shells out: a stub script that echoes a canned verdict
    /// drives the subprocess transport end to end, with no network and no codex.
    @Test func subprocessRunnerExecutesTheInjectedExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aski56-judge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appending(path: "stub-judge.sh")
        try """
        #!/bin/bash
        echo "reasoning about structure then tone"
        echo "VERDICT: SECOND"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        let runner = Arbiter.Judge.SubprocessRunner(
            executable: script.path,
            argumentTemplate: Arbiter.Judge.defaultArgumentTemplate)
        let (reference, left, right) = Self.urls()
        let output = try runner.judge(
            reference: reference, first: left, second: right, prompt: "prompt text")
        #expect(Arbiter.Judge.parseVerdict(output) == .second)
    }

    /// A judge call that never returns must not hang the run. A full VLM leg is
    /// 40 pairs x 6 calls; one wedged subprocess with no deadline stalls all of
    /// them forever. The timeout kills the call and hands back whatever text
    /// arrived, which carries no `VERDICT:` line — so the §2.2 machinery retries
    /// once and then records `invalid`, counting the wedged call toward neither
    /// side. That is the correct disposition, and it is the one a hang denies.
    @Test func aWedgedSubprocessIsKilledAtTheTimeoutAndYieldsNoVerdict() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aski56-judge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appending(path: "wedged-judge.sh")
        try """
        #!/bin/bash
        echo "thinking about structure"
        sleep 120
        echo "VERDICT: FIRST"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        let runner = Arbiter.Judge.SubprocessRunner(
            executable: script.path,
            argumentTemplate: Arbiter.Judge.defaultArgumentTemplate,
            timeout: 1)
        let (reference, left, right) = Self.urls()
        let started = Date()
        let output = try runner.judge(
            reference: reference, first: left, second: right, prompt: "prompt text")
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 30, "the runner waited \(elapsed)s on a 1s timeout")
        #expect(Arbiter.Judge.parseVerdict(output) == nil)
    }

    /// The harder timeout case, and the one a real `codex` invocation actually
    /// produces: the direct child exits promptly but leaves a GRANDCHILD holding
    /// the pipe's write end. Killing only the direct child leaves the drain
    /// blocked in `availableData` with no EOF ever arriving, so the call hangs
    /// anyway and leaks a thread and two descriptors per attempt — 240 calls of
    /// that exhausts the process. The runner has to kill the whole process group
    /// and close the read end so the drain unblocks.
    @Test func aGrandchildHoldingThePipeDoesNotOutliveTheTimeout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aski56-judge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let marker = directory.appending(path: "grandchild-still-alive")
        let script = directory.appending(path: "leaky-judge.sh")
        // The grandchild inherits stdout, is disowned, and outlives its parent.
        // If it survives the timeout it touches the marker file.
        try """
        #!/bin/bash
        echo "thinking about structure"
        ( sleep 6; touch "\(marker.path)" ) &
        disown
        exit 0
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        let runner = Arbiter.Judge.SubprocessRunner(
            executable: script.path,
            argumentTemplate: Arbiter.Judge.defaultArgumentTemplate,
            timeout: 1)
        let (reference, left, right) = Self.urls()
        let started = Date()
        let output = try runner.judge(
            reference: reference, first: left, second: right, prompt: "prompt text")
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 20, "the drain never unblocked: waited \(elapsed)s on a 1s timeout")
        #expect(Arbiter.Judge.parseVerdict(output) == nil)

        // Give the grandchild's own sleep time to fire if it was never killed.
        Thread.sleep(forTimeInterval: 8)
        #expect(
            !FileManager.default.fileExists(atPath: marker.path),
            "the grandchild outlived the timeout — the process group was not killed")
    }

    /// The frozen prompt attaches images with "no filenames, metrics, or
    /// provenance", but the paths still reach the judge on its command line.
    /// `pair-007-left.png` names the side, and a judge that reads its own argv —
    /// or a launcher that echoes it — can tell which image is which under both
    /// presentation orders, which is exactly what the order swap is there to
    /// hide. Every path handed to the runner must be position-neutral.
    @Test func theRunnerNeverSeesAPathNamingASide() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aski56-neutral-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pair = Arbiter.Pair(
            id: "pair-007", family: .validation,
            source: .init(corpus: "nasa-steerable-v1", asset: "sahara-dunes.png"),
            charset: "blocks", armA: .init(name: "F"), armB: .init(name: "P"),
            leftIsArmA: true,
            metrics: Arbiter.PairMetrics(armAMeans: [.mae: 0.2], armBMeans: [.mae: 0.5]),
            repeatOf: nil)
        for name in ["\(pair.id)-ref.png", "\(pair.id)-left.png", "\(pair.id)-right.png"] {
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: directory.appending(path: name))
        }

        let runner = ScriptedRunner(Array(repeating: "VERDICT: FIRST", count: 6))
        _ = try Arbiter.Judge.judgePair(
            pair: pair, directory: directory, runner: runner, config: .default)

        #expect(runner.calls.count == 6)
        for call in runner.calls {
            for url in [call.reference, call.first, call.second] {
                let path = url.path.lowercased()
                #expect(!path.contains("left"), "a side name reached the judge: \(url.path)")
                #expect(!path.contains("right"), "a side name reached the judge: \(url.path)")
                // The arm and the source must not leak through the path either.
                #expect(!path.contains("sahara"))
                #expect(!path.contains("blocks"))
            }
            #expect(call.allReadable, "a staged image was missing when the judge was called")
            #expect(call.first != call.second)

            // The basenames are the same three in both orders, so the argv
            // differs only in the opaque staging segment.
            #expect(call.reference.lastPathComponent == "reference.png")
            #expect(call.first.lastPathComponent == "first.png")
            #expect(call.second.lastPathComponent == "second.png")
        }

        // The staging directory name must be opaque too. Naming it for the
        // presentation order ("a" / "b") puts the order straight back into the
        // argv that the neutral basenames just took out of it.
        let stagingNames = Set(
            runner.calls.map { $0.first.deletingLastPathComponent().lastPathComponent })
        #expect(stagingNames.count == 2, "expected one staging directory per order")
        for name in stagingNames {
            #expect(UUID(uuidString: name) != nil, "staging directory is not opaque: \(name)")
        }

        // And the two orders' argv are identical apart from that opaque token.
        let byOrder = Dictionary(grouping: runner.calls) {
            $0.first.deletingLastPathComponent().lastPathComponent
        }
        let shapes = byOrder.values.map { calls in
            calls.map {
                [$0.reference, $0.first, $0.second].map(\.lastPathComponent).joined(separator: ",")
            }
        }
        #expect(shapes.count == 2)
        #expect(shapes[0] == shapes[1], "the two presentation orders have distinguishable argv")
    }

    /// An injected `--runner` with no `--runner-arg` must still be handed the
    /// three images and the prompt. An empty argument template invokes the judge
    /// with NO arguments at all, so it never sees a single image — and because a
    /// judge that cannot see the images still emits *something*, the leg fills up
    /// with verdicts that are pure position bias and the run looks like it
    /// worked. Every call must carry the substituted paths.
    @Test func anInjectedRunnerWithoutExplicitArgsStillReceivesTheImages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aski56-argv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let log = directory.appending(path: "argv.log")
        let script = directory.appending(path: "echo-argv.sh")
        try """
        #!/bin/bash
        printf '%s\\n' "$*" >> "\(log.path)"
        echo "VERDICT: FIRST"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        let config = Arbiter.Judge.Config.injected(executable: script.path, arguments: [])
        let runner = Arbiter.Judge.SubprocessRunner(
            executable: config.executable, argumentTemplate: config.argumentTemplate)
        let reference = directory.appending(path: "ref.png")
        let first = directory.appending(path: "first.png")
        let second = directory.appending(path: "second.png")
        for url in [reference, first, second] { try Data([0x89]).write(to: url) }

        let output = try runner.judge(
            reference: reference, first: first, second: second, prompt: "the frozen prompt")
        #expect(Arbiter.Judge.parseVerdict(output) == .first)

        let recorded = try String(contentsOf: log, encoding: .utf8)
        #expect(recorded.contains(reference.path), "the judge was never given the reference")
        #expect(recorded.contains(first.path), "the judge was never given the first image")
        #expect(recorded.contains(second.path), "the judge was never given the second image")
        #expect(recorded.contains("the frozen prompt"), "the judge was never given the prompt")
    }

    /// A hand-written `--runner-arg` list that forgets the image placeholders is
    /// the same failure with a different cause, so the config refuses it rather
    /// than running 240 blind calls.
    @Test func anInjectedTemplateMissingTheImagePlaceholdersIsRejected() {
        #expect(throws: ArbiterError.self) {
            _ = try Arbiter.Judge.Config.validatedInjected(
                executable: "/bin/echo", arguments: ["--model", "something"])
        }
        #expect(throws: Never.self) {
            _ = try Arbiter.Judge.Config.validatedInjected(
                executable: "/bin/echo",
                arguments: [
                    "-i", Arbiter.Judge.referencePlaceholder,
                    "-i", Arbiter.Judge.firstPlaceholder,
                    "-i", Arbiter.Judge.secondPlaceholder,
                    Arbiter.Judge.promptPlaceholder,
                ])
        }
    }

    /// §2.2's default pin invokes `codex` by bare name, so the spawn MUST search
    /// PATH. `posix_spawn` does not — it treats its path argument as a literal
    /// filename and fails ENOENT — which would make the pinned configuration the
    /// one configuration that cannot run, while `--runner` (the workaround)
    /// relabels `model_id` to `injected:codex` and the effort to `unspecified`
    /// and so misreports the pin in `judge.json`.
    @Test func aBareExecutableNameIsResolvedThroughPATH() throws {
        #expect(
            !Arbiter.Judge.defaultExecutable.contains("/"),
            "the default pin is a bare name, which is what makes PATH search load-bearing")

        let runner = Arbiter.Judge.SubprocessRunner(
            executable: "echo", argumentTemplate: ["VERDICT:", "SECOND"])
        let (reference, left, right) = Self.urls()
        let output = try runner.judge(
            reference: reference, first: left, second: right, prompt: "p")
        #expect(Arbiter.Judge.parseVerdict(output) == .second)
    }

    /// A call that succeeds must not pay the timeout machinery's price. The
    /// drain thread signals its semaphore exactly once; the happy path consumed
    /// that signal and then waited on it a second time, so every successful call
    /// sat out the full 2s grace period — roughly eight dead minutes across a
    /// 240-call leg, on top of the judge's own latency.
    @Test func aSuccessfulCallDoesNotWaitOutTheGracePeriod() throws {
        let runner = Arbiter.Judge.SubprocessRunner(
            executable: "echo", argumentTemplate: ["VERDICT:", "FIRST"], timeout: 30)
        let (reference, left, right) = Self.urls()

        // Warm once so the measurement is not paying first-spawn costs.
        // The 1.75s ceiling tolerates loaded-host spawn jitter while remaining
        // below the old defect's mandatory 2s grace wait.
        _ = try runner.judge(reference: reference, first: left, second: right, prompt: "p")

        let started = Date()
        for _ in 0..<3 {
            let output = try runner.judge(
                reference: reference, first: left, second: right, prompt: "p")
            #expect(Arbiter.Judge.parseVerdict(output) == .first)
        }
        let perCall = Date().timeIntervalSince(started) / 3
        // Leave scheduling headroom while staying below the 2s regression signature.
        #expect(
            perCall < 1.75,
            "a trivial successful call took \(perCall)s; expected below the 2s grace period")
    }

    /// The judge config is the reproducibility record: transport, exact model
    /// ID, effort, the frozen prompt and its SHA-256, K, and the order policy.
    @Test func judgeConfigPinsTheFrozenPromptAndSampling() throws {
        let config = Arbiter.Judge.Config.default
        #expect(config.transport == "subprocess")
        #expect(config.modelID == "gpt-5.6-terra")
        #expect(config.reasoningEffort == "xhigh")
        #expect(config.samplesPerOrder == 3)
        #expect(config.orderPolicy == "both-orders-must-agree")
        #expect(config.prompt == Arbiter.Judge.frozenPrompt)
        #expect(config.promptSHA256 == Arbiter.Judge.sha256Hex(Arbiter.Judge.frozenPrompt))
        #expect(config.promptSHA256.count == 64)

        // The frozen prompt text itself, so an edit is a reviewed change.
        #expect(Arbiter.Judge.frozenPrompt.contains("reference photograph"))
        #expect(Arbiter.Judge.frozenPrompt.contains("VERDICT: FIRST"))
        #expect(Arbiter.Judge.frozenPrompt.contains("VERDICT: SECOND"))
        #expect(!Arbiter.Judge.frozenPrompt.lowercased().contains("mae"))
    }
}
