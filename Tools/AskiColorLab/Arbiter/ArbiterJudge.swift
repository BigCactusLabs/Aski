import CryptoKit
import Foundation

/// The transport the VLM leg speaks through. Injected so the whole leg —
/// prompting, parsing, retry, aggregation — is testable with a stub script and
/// no network.
protocol ArbiterJudgeRunner: Sendable {
    /// Present one triplet and return the judge's raw reply text.
    func judge(reference: URL, first: URL, second: URL, prompt: String) throws -> String
}

extension Arbiter {

    /// ASKI-56 §2.2, the VLM leg.
    ///
    /// The leg is a **pre-screen and tie-breaker, never co-equal** (§1), and its
    /// verdicts count for nothing until the §5.1 gate passes. What makes it an
    /// instrument rather than a coin flip is the both-orders decide rule: each
    /// pair is judged in both presentation orders, K times each, and it decides
    /// for a side only when both order-majorities agree. A judge with a position
    /// bias — answer "first" whatever is shown — produces a tie under that rule
    /// instead of a 6-0 verdict for whichever side led.
    ///
    /// Frontier survey finding this encodes: pairwise VLM judging tracks humans
    /// on clearly separated pairs and degrades on near-ties, and frozen API pins
    /// do not buy determinism in 2026 — so reproducibility is the exact model ID
    /// plus K repeated samples plus published per-pair vote splits, all of which
    /// this records.
    enum Judge {

        // MARK: - Frozen prompt

        /// §2.2's frozen prompt. Images are attached in order: reference, first,
        /// second. No filenames, no metrics, no provenance.
        ///
        /// Editing this string changes the judge config, which under §2.2's
        /// upgrade path requires re-passing the §5.1 validation gate before any
        /// verdict counts. The SHA-256 travels in `judge.json` so that cannot
        /// happen silently.
        static let frozenPrompt = """
            The first image is a reference photograph. The second and third images are two ASCII-art \
            renderings of it. Which rendering preserves the reference's structure and tonality more \
            faithfully? Think briefly about structure, then tone. End with exactly one line: \
            `VERDICT: FIRST` or `VERDICT: SECOND`.
            """

        static func sha256Hex(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        // MARK: - Config

        /// The reproducibility record embedded in the run manifest (§2.2).
        struct Config: Sendable, Codable, Equatable {
            let transport: String
            let executable: String
            let argumentTemplate: [String]
            let modelID: String
            let reasoningEffort: String
            let prompt: String
            let promptSHA256: String
            let samplesPerOrder: Int
            let orderPolicy: String

            enum CodingKeys: String, CodingKey {
                case transport
                case executable
                case argumentTemplate = "argument_template"
                case modelID = "model_id"
                case reasoningEffort = "reasoning_effort"
                case prompt
                case promptSHA256 = "prompt_sha256"
                case samplesPerOrder = "samples_per_order"
                case orderPolicy = "order_policy"
            }

            /// The §2.2 default pin.
            static let `default` = Config(
                transport: "subprocess",
                executable: defaultExecutable,
                argumentTemplate: defaultArgumentTemplate,
                modelID: defaultModelID,
                reasoningEffort: defaultReasoningEffort,
                prompt: frozenPrompt,
                promptSHA256: sha256Hex(frozenPrompt),
                samplesPerOrder: defaultSamplesPerOrder,
                orderPolicy: "both-orders-must-agree")

            /// A config for an injected runner, with the pin fields relabeled so
            /// a stub run can never be mistaken for a pinned one.
            ///
            /// An EMPTY argument list falls back to the neutral template rather
            /// than to no arguments at all. A judge invoked with no arguments
            /// never sees a single image, and because it still answers
            /// something, the leg fills with pure position bias while looking
            /// like it ran.
            static func injected(executable: String, arguments: [String]) -> Config {
                Config(
                    transport: "subprocess",
                    executable: executable,
                    argumentTemplate: arguments.isEmpty ? neutralArgumentTemplate : arguments,
                    modelID: "injected:\(URL(fileURLWithPath: executable).lastPathComponent)",
                    reasoningEffort: "unspecified",
                    prompt: frozenPrompt,
                    promptSHA256: sha256Hex(frozenPrompt),
                    samplesPerOrder: defaultSamplesPerOrder,
                    orderPolicy: "both-orders-must-agree")
            }

            /// `injected`, but refusing a hand-written template that cannot show
            /// the judge the images. 240 blind calls that each return a
            /// confident verdict is the most expensive possible way to learn
            /// that a `--runner-arg` list was wrong.
            static func validatedInjected(
                executable: String, arguments: [String]
            ) throws -> Config {
                let config = injected(executable: executable, arguments: arguments)
                let required = [referencePlaceholder, firstPlaceholder, secondPlaceholder]
                let missing = required.filter { !config.argumentTemplate.contains($0) }
                guard missing.isEmpty else {
                    throw ArbiterError.judgeTemplateMissingPlaceholders(missing)
                }
                return config
            }
        }

        /// The argument template used for an injected runner that supplied none:
        /// the three images and the prompt, in the order the frozen prompt
        /// describes, with no vendor-specific flags.
        static let neutralArgumentTemplate: [String] = [
            referencePlaceholder, firstPlaceholder, secondPlaceholder, promptPlaceholder,
        ]

        /// §2.2's default pin: `codex exec -s read-only -m gpt-5.6-terra
        /// -c model_reasoning_effort=xhigh -i <ref> -i <first> -i <second>
        /// --skip-git-repo-check`.
        static let defaultExecutable = "codex"
        static let defaultModelID = "gpt-5.6-terra"
        static let defaultReasoningEffort = "xhigh"
        /// K = 3 samples per presentation order; 2 orders -> 6 calls per pair.
        static let defaultSamplesPerOrder = 3

        /// Placeholders the runner substitutes per call.
        static let referencePlaceholder = "{reference}"
        static let firstPlaceholder = "{first}"
        static let secondPlaceholder = "{second}"
        static let promptPlaceholder = "{prompt}"

        static let defaultArgumentTemplate: [String] = [
            "exec", "-s", "read-only",
            "-m", defaultModelID,
            "-c", "model_reasoning_effort=\(defaultReasoningEffort)",
            "-i", referencePlaceholder,
            "-i", firstPlaceholder,
            "-i", secondPlaceholder,
            "--skip-git-repo-check",
            promptPlaceholder,
        ]

        // MARK: - Verdicts

        /// What one call produced, in the call's own FIRST/SECOND vocabulary.
        enum RawVerdict: String, Sendable, Codable, Equatable {
            case first = "FIRST"
            case second = "SECOND"
            /// No parseable verdict after the one permitted retry. Counts toward
            /// neither side (§2.2).
            case invalid
        }

        /// Which side was presented first.
        enum Order: String, Sendable, Codable, Equatable, CaseIterable {
            case leftFirst = "left-first"
            case rightFirst = "right-first"

            /// Map a call's FIRST/SECOND onto the pair's left/right.
            func side(for verdict: RawVerdict) -> Decision? {
                switch (self, verdict) {
                case (.leftFirst, .first), (.rightFirst, .second): return .left
                case (.leftFirst, .second), (.rightFirst, .first): return .right
                default: return nil
                }
            }
        }

        /// A decided side, or the tie the both-orders rule produces on
        /// disagreement.
        enum Decision: String, Sendable, Codable, Equatable {
            case left = "L"
            case right = "R"
            case tie
        }

        struct Call: Sendable, Codable, Equatable {
            let order: Order
            let sample: Int
            let verdict: RawVerdict
            /// Whether the one permitted retry was spent on this call (§2.2).
            let retried: Bool

            init(order: Order, sample: Int, verdict: RawVerdict, retried: Bool) {
                self.order = order
                self.sample = sample
                self.verdict = verdict
                self.retried = retried
            }
        }

        struct VoteSplit: Sendable, Codable, Equatable {
            let left: Int
            let right: Int
            let invalid: Int
        }

        /// One pair's judged result, carrying the raw split of all six verdicts
        /// — §2.2 makes that split the published reproducibility substitute for
        /// a temperature control the 2026 APIs no longer expose.
        struct PairJudgement: Sendable, Codable, Equatable {
            let pairID: String
            let calls: [Call]
            let decision: Decision

            enum CodingKeys: String, CodingKey {
                case pairID = "pair_id"
                case calls
                case decision
                case voteSplit = "vote_split"
                case orderMajorities = "order_majorities"
            }

            init(pairID: String, calls: [Call], decision: Decision) {
                self.pairID = pairID
                self.calls = calls
                self.decision = decision
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                pairID = try container.decode(String.self, forKey: .pairID)
                calls = try container.decode([Call].self, forKey: .calls)
                decision = try container.decode(Decision.self, forKey: .decision)
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(pairID, forKey: .pairID)
                try container.encode(calls, forKey: .calls)
                try container.encode(decision, forKey: .decision)
                try container.encode(voteSplit, forKey: .voteSplit)
                try container.encode(
                    Dictionary(
                        uniqueKeysWithValues: Order.allCases.map {
                            ($0.rawValue, orderMajority($0)?.rawValue ?? "none")
                        }),
                    forKey: .orderMajorities)
            }

            /// All calls' verdicts resolved to sides, and the invalid count.
            var voteSplit: VoteSplit {
                var left = 0, right = 0, invalid = 0
                for call in calls {
                    switch call.order.side(for: call.verdict) {
                    case .left: left += 1
                    case .right: right += 1
                    default: invalid += 1
                    }
                }
                return VoteSplit(left: left, right: right, invalid: invalid)
            }

            /// The majority side within one presentation order, or `nil` when
            /// that order has no majority — every call invalid, or a dead split.
            func orderMajority(_ order: Order) -> Decision? {
                var left = 0, right = 0
                for call in calls where call.order == order {
                    switch order.side(for: call.verdict) {
                    case .left: left += 1
                    case .right: right += 1
                    default: break
                    }
                }
                if left > right { return .left }
                if right > left { return .right }
                return nil
            }
        }

        // MARK: - Parsing

        /// The LAST `VERDICT:` line wins. The frozen prompt asks the judge to
        /// think first, and reasoning text routinely quotes the target format
        /// mid-stream, so a first-match parser reads the instruction back as the
        /// answer. Matching is exact — an upper-case `VERDICT:` followed by
        /// `FIRST` or `SECOND` — because a case-insensitive parser would accept
        /// prose like "the verdict: first impressions favour…".
        static func parseVerdict(_ text: String) -> RawVerdict? {
            var found: RawVerdict?
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`*"))
                guard trimmed.hasPrefix("VERDICT:") else { continue }
                let tail = trimmed.dropFirst("VERDICT:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`*."))
                if let verdict = RawVerdict(rawValue: tail), verdict != .invalid {
                    found = verdict
                }
            }
            return found
        }

        // MARK: - One call, with the §2.2 retry-once policy

        struct CallResult: Sendable {
            let verdict: RawVerdict
            let retried: Bool
            let transcript: String
        }

        /// Runs one judgement. An unparseable reply is retried EXACTLY once and
        /// then recorded `invalid` — a wider retry budget would quietly resample
        /// the judge until it produced a parseable answer, which biases toward
        /// whatever the judge finds easy to say.
        static func call(
            runner: ArbiterJudgeRunner, reference: URL, first: URL, second: URL, prompt: String
        ) throws -> CallResult {
            let firstReply = try runner.judge(
                reference: reference, first: first, second: second, prompt: prompt)
            if let verdict = parseVerdict(firstReply) {
                return CallResult(verdict: verdict, retried: false, transcript: firstReply)
            }
            let retryReply = try runner.judge(
                reference: reference, first: first, second: second, prompt: prompt)
            if let verdict = parseVerdict(retryReply) {
                return CallResult(verdict: verdict, retried: true, transcript: retryReply)
            }
            return CallResult(verdict: .invalid, retried: true, transcript: retryReply)
        }

        // MARK: - Aggregation

        /// §2.2's decide rule: a pair is decided for a side **only if both
        /// order-majorities agree**; otherwise it is a VLM tie.
        static func aggregate(pairID: String, calls: [Call]) -> PairJudgement {
            let judgement = PairJudgement(pairID: pairID, calls: calls, decision: .tie)
            let leftOrder = judgement.orderMajority(.leftFirst)
            let rightOrder = judgement.orderMajority(.rightFirst)
            guard let leftOrder, let rightOrder, leftOrder == rightOrder else {
                return judgement
            }
            return PairJudgement(pairID: pairID, calls: calls, decision: leftOrder)
        }

        /// Judge one pair end to end: both orders × K samples.
        ///
        /// The images are re-staged under position-neutral names before any call.
        /// The frozen prompt promises "no filenames, metrics, or provenance", but
        /// the paths themselves still reach the judge on its command line, and
        /// `pair-007-left.png` names the side outright — which is precisely what
        /// the both-orders swap exists to conceal. Each order gets its own
        /// staging directory holding `reference.png`, `first.png`, `second.png`,
        /// so the argv is identical in both orders and carries no side, no arm,
        /// no charset and no source.
        static func judgePair(
            pair: Pair, directory: URL, runner: ArbiterJudgeRunner, config: Config
        ) throws -> PairJudgement {
            let reference = directory.appending(path: "\(pair.id)-ref.png")
            let left = directory.appending(path: "\(pair.id)-left.png")
            let right = directory.appending(path: "\(pair.id)-right.png")

            let staging = FileManager.default.temporaryDirectory
                .appending(path: "aski56-judge-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }

            var calls: [Call] = []
            for order in Order.allCases {
                let (firstSource, secondSource) =
                    order == .leftFirst ? (left, right) : (right, left)
                // Opaque, not "a"/"b": a staging directory named for its
                // position puts the presentation order back into the argv that
                // the neutral filenames just took out of it.
                let stage = staging.appending(path: UUID().uuidString)
                try FileManager.default.createDirectory(
                    at: stage, withIntermediateDirectories: true)
                let neutralReference = stage.appending(path: "reference.png")
                let neutralFirst = stage.appending(path: "first.png")
                let neutralSecond = stage.appending(path: "second.png")
                for (source, destination) in [
                    (reference, neutralReference), (firstSource, neutralFirst),
                    (secondSource, neutralSecond),
                ] {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: source, to: destination)
                }

                for sample in 0..<config.samplesPerOrder {
                    let result = try call(
                        runner: runner, reference: neutralReference, first: neutralFirst,
                        second: neutralSecond, prompt: config.prompt)
                    calls.append(
                        Call(
                            order: order, sample: sample, verdict: result.verdict,
                            retried: result.retried))
                }
            }
            return aggregate(pairID: pair.id, calls: calls)
        }

        // MARK: - Subprocess transport

        /// Shared state between the calling thread and its drain thread: the
        /// child's merged output so far — readable even after a timeout cut the
        /// child off mid-answer — and the flag that asks the drain to stop.
        private final class DrainState: @unchecked Sendable {
            private let lock = NSLock()
            private var data = Data()
            private var abandoned = false

            func append(_ chunk: Data) {
                lock.lock()
                defer { lock.unlock() }
                data.append(chunk)
            }

            var snapshot: Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }

            /// Ask the drain to stop reading. Only reached when something
            /// outside the killed process group still holds the pipe's write
            /// end, so no EOF is ever coming.
            func abandon() {
                lock.lock()
                defer { lock.unlock() }
                abandoned = true
            }

            var isAbandoned: Bool {
                lock.lock()
                defer { lock.unlock() }
                return abandoned
            }
        }

        /// `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, which is the only way to
        /// get a new process group on Darwin — `Process.startNewProcessGroup`
        /// exists in swift-corelibs-foundation and not in Darwin Foundation.
        /// The group is what makes the timeout able to kill a judge's helper
        /// processes instead of only the launcher that spawned them.
        enum Spawn {
            struct Child {
                let pid: pid_t
                /// Read end of the merged stdout/stderr pipe. The caller owns it
                /// and must `close` it.
                let readFD: Int32
            }

            enum Failure: Error, CustomStringConvertible {
                case pipe(Int32)
                case spawn(String, Int32)

                var description: String {
                    switch self {
                    case .pipe(let code): return "could not create the judge pipe (errno \(code))"
                    case .spawn(let executable, let code):
                        return "could not spawn the judge '\(executable)' (errno \(code))"
                    }
                }
            }

            static func run(executable: String, arguments: [String]) throws -> Child {
                var fds: [Int32] = [-1, -1]
                guard pipe(&fds) == 0 else { throw Failure.pipe(errno) }
                let readFD = fds[0]
                let writeFD = fds[1]

                var actions: posix_spawn_file_actions_t?
                posix_spawn_file_actions_init(&actions)
                defer { posix_spawn_file_actions_destroy(&actions) }
                // stdin from /dev/null: a judge that reads stdin must see EOF
                // rather than inheriting — and blocking on — our own.
                posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
                posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO)
                posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO)
                posix_spawn_file_actions_addclose(&actions, readFD)
                posix_spawn_file_actions_addclose(&actions, writeFD)

                var attributes: posix_spawnattr_t?
                posix_spawnattr_init(&attributes)
                defer { posix_spawnattr_destroy(&attributes) }
                posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
                // pgroup 0 means "make the child its own group leader", so the
                // group id equals the child's pid.
                posix_spawnattr_setpgroup(&attributes, 0)

                let argv: [String] = [executable] + arguments
                var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
                cArgv.append(nil)
                defer { for pointer in cArgv where pointer != nil { free(pointer) } }

                var pid: pid_t = 0
                // `posix_spawnp`, not `posix_spawn`: §2.2's default pin invokes
                // `codex` by bare name, and `posix_spawn` treats its path
                // argument as a literal filename and fails ENOENT. Without PATH
                // search the pinned configuration is the one configuration that
                // cannot run, and the only workaround — `--runner codex` — files
                // the run under `model_id: injected:codex` with an unspecified
                // effort, misreporting the pin in `judge.json`.
                let status = posix_spawnp(&pid, executable, &actions, &attributes, cArgv, environ)
                close(writeFD)
                guard status == 0 else {
                    close(readFD)
                    throw Failure.spawn(executable, status)
                }
                return Child(pid: pid, readFD: readFD)
            }
        }

        /// Runs the injected executable with the placeholders substituted. This
        /// is the only place the leg touches the outside world, and `--runner`
        /// replaces it wholesale — tests drive a stub script through exactly
        /// this path.
        struct SubprocessRunner: ArbiterJudgeRunner {
            let executable: String
            let argumentTemplate: [String]
            /// Deadline for one call. A full leg is 40 pairs x 6 calls, so a
            /// single wedged child with no deadline stalls every remaining call
            /// forever. On expiry the child is killed and the partial output is
            /// returned, which carries no `VERDICT:` line — so the §2.2 machinery
            /// retries once and then records `invalid`, counting the wedged call
            /// toward neither side. That is the disposition a hang denies.
            let timeout: TimeInterval

            init(
                executable: String, argumentTemplate: [String],
                timeout: TimeInterval = 600
            ) {
                self.executable = executable
                self.argumentTemplate = argumentTemplate
                self.timeout = timeout
            }

            func judge(reference: URL, first: URL, second: URL, prompt: String) throws -> String {
                let arguments = argumentTemplate.map { argument -> String in
                    switch argument {
                    case referencePlaceholder: return reference.path
                    case firstPlaceholder: return first.path
                    case secondPlaceholder: return second.path
                    case promptPlaceholder: return prompt
                    default: return argument
                    }
                }
                // Spawn as the leader of its OWN process group. A judge like
                // `codex` is a launcher: it spawns helpers that inherit stdout
                // and can outlive it. Signalling only the direct child leaves
                // those helpers holding the pipe's write end, so no EOF ever
                // arrives and the drain below never returns — the call hangs
                // anyway and leaks a thread and two descriptors, 240 times over.
                // One `killpg` on the group reaches the whole tree.
                //
                // `Process` cannot do this on Darwin (`startNewProcessGroup` is
                // corelibs-only), so the spawn is done directly with
                // `POSIX_SPAWN_SETPGROUP`.
                let child = try Spawn.run(executable: executable, arguments: arguments)

                // Drain on its own thread. A child that fills the 64K pipe
                // buffer blocks until someone reads, so waiting for exit first
                // and reading afterwards deadlocks on any verbose judge.
                //
                // The thread OWNS `readFD` and is the only code that closes it.
                // The parent closing it while the thread sits in `read` would
                // free the descriptor number for reuse, and the next call's pipe
                // could land on the same number — quietly attributing one pair's
                // output to another's. Ownership here makes that unrepresentable
                // rather than merely unlikely.
                //
                // The loop polls rather than blocking outright so it can notice
                // `abandon()`. Everything in the child's process group is dead by
                // the time we abandon, but a helper that escaped the group could
                // still hold the write end, and a `read` blocked on that would
                // never return: the poll tick is what guarantees this thread
                // always terminates, so neither it nor the descriptor leaks.
                let drain = DrainState()
                let drained = DispatchSemaphore(value: 0)
                let readFD = child.readFD
                Thread.detachNewThread {
                    defer {
                        close(readFD)
                        drained.signal()
                    }
                    var scratch = [UInt8](repeating: 0, count: 16 * 1024)
                    var descriptor = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
                    while !drain.isAbandoned {
                        let ready = poll(&descriptor, 1, 200)
                        if ready < 0 {
                            if errno == EINTR { continue }
                            break
                        }
                        if ready == 0 { continue }
                        let count = scratch.withUnsafeMutableBytes {
                            read(readFD, $0.baseAddress, $0.count)
                        }
                        if count > 0 {
                            drain.append(Data(scratch[0..<count]))
                        } else if count == 0 || errno != EINTR {
                            break
                        }
                    }
                }

                // Wait ONCE for the drain, and remember whether that wait
                // consumed the signal. The drain signals exactly once, so a
                // second unconditional wait on the success path can never be
                // satisfied and simply burns the whole grace period on every
                // call that worked — which is most of them.
                var drainFinished = drained.wait(timeout: .now() + timeout) == .success
                if !drainFinished {
                    // The group id is the child's own pid, and the child is not
                    // reaped until below, so the pid cannot have been recycled
                    // onto an unrelated process between here and the signal —
                    // the TOCTOU window a bare `kill(pid)` would have.
                    kill(-child.pid, SIGTERM)
                    drainFinished = drained.wait(timeout: .now() + 2) == .success
                    if !drainFinished {
                        kill(-child.pid, SIGKILL)
                        drainFinished = drained.wait(timeout: .now() + 2) == .success
                    }
                    if !drainFinished {
                        // Something outside the group still holds the write end.
                        // Tell the drain to stop; it exits within one poll tick
                        // and closes the descriptor itself.
                        drain.abandon()
                        _ = drained.wait(timeout: .now() + 2)
                    }
                }

                // Reap, so a 240-call leg does not accumulate zombies. Bounded
                // in practice by the kills above; left as a plain blocking wait
                // because the group is dead before we get here.
                var status: Int32 = 0
                while waitpid(child.pid, &status, 0) < 0 && errno == EINTR {}
                return String(decoding: drain.snapshot, as: UTF8.self)
            }
        }
    }
}
