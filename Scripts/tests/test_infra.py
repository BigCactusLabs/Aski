"""Exercise shell orchestration with fake Apple tools; never build or render Aski.

Run with Python 3's standard library: python3 -B -m unittest discover -s Scripts/tests -v
Every test uses a disposable repository and a private TMPDIR, including spaces.
"""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]

XCRUN = r'''#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$*" in
    'swift --version')
        echo "Apple Swift version ${MOCK_SWIFT_VERSION:-6.4} (mock)"
        exit "${MOCK_SWIFT_STATUS:-0}" ;;
    '--find swift') echo '/mock toolchain/swift' ;;
    '--find metal'|'--find metallib') echo '/mock toolchain/metal' ;;
    '--show-sdk-path') echo '/mock SDK'; exit "${MOCK_SDK_STATUS:-0}" ;;
    '--show-sdk-version') echo '27.0' ;;
    'swift package resolve')
        echo "${MOCK_MESSAGE:-resolve}"
        if [ -n "${MOCK_READY:-}" ]; then
            touch "$MOCK_READY"
            while [ ! -f "$MOCK_RELEASE" ]; do sleep 0.02; done
        fi
        if [ "${MOCK_RESOLVE_CHANGE:-0}" = 1 ]; then echo changed >> Package.resolved; fi
        exit "${MOCK_RESOLVE_STATUS:-0}" ;;
    'swift run BuildKernelLibrary')
        if [ "${MOCK_KERNEL:-same}" != same ]; then
            printf 'regenerated' > Sources/Aski/Resources/Kernels/default.metallib
        fi
        if [ -n "${MOCK_KERNEL_CHILD_READY:-}" ]; then
            bash -c '
                trap '\''sleep 0.1; printf shutdown-write > Sources/Aski/Resources/Kernels/default.metallib; printf stopped > "$MOCK_KERNEL_CHILD_STOPPED"; exit 0'\'' TERM
                touch "$MOCK_KERNEL_CHILD_READY"
                while [ ! -f "$MOCK_RELEASE" ]; do sleep 0.02; done
                printf late-write > Sources/Aski/Resources/Kernels/default.metallib
            ' &
            wait "$!"
        fi
        if [ -n "${MOCK_READY:-}" ]; then
            touch "$MOCK_READY"
            while [ ! -f "$MOCK_RELEASE" ]; do sleep 0.02; done
        fi
        exit "${MOCK_KERNEL_STATUS:-0}" ;;
    'swift package dump-symbol-graph --minimum-access-level public')
        mkdir -p .build/mock/symbolgraph
        if [ "${MOCK_MISSING_GRAPH:-0}" != 1 ]; then
            printf '{"module":{"name":"Aski"}}\n' > .build/mock/symbolgraph/Aski.symbols.json
        fi
        # Match the known whole-package nonzero exit with a valid Aski graph.
        exit 1 ;;
    'docc convert --help')
        echo --enable-experimental-markdown-output
        if [ "${MOCK_MISSING_MANIFEST_FLAG:-0}" != 1 ]; then
            echo --enable-experimental-markdown-output-manifest
        fi ;;
    'docc convert '*)
        output=''
        markdown=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output-path) output="$2"; shift ;;
                --enable-experimental-markdown-output) markdown=1 ;;
            esac
            shift
        done
        [ -n "$output" ] || exit 98
        mkdir -p "$output"
        echo artifact > "$output/mock-artifact.txt"
        if [ -n "${MOCK_READY:-}" ]; then
            touch "$MOCK_READY"
            while [ ! -f "$MOCK_RELEASE" ]; do sleep 0.02; done
        fi
        if [ "$markdown" = 1 ]; then exit "${MOCK_MARKDOWN_STATUS:-0}"; fi
        exit "${MOCK_DOCC_STATUS:-0}" ;;
    *) echo "unexpected mock xcrun command: $*" >&2; exit 97 ;;
esac
'''


class InfraTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aski infra tests ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / "checkout with spaces"
        self.tmp = self.home / "private tmp"
        self.bin = self.home / "mock tools"
        for path in (self.repo / "Scripts", self.tmp, self.bin):
            path.mkdir(parents=True)
        for name in ("repo-doctor.sh", "validate-docc.sh"):
            shutil.copyfile(SCRIPTS / name, self.repo / "Scripts" / name)
        self.write("Package.swift", "// swift-tools-version: 6.3\n")
        self.write("Package.resolved", "{}\n")
        self.write("Sources/Aski/Example.swift", "public struct Example {}\n")
        self.write("Sources/Aski/Aski.docc/Aski.md", "# Aski\n")
        self.write("Sources/Aski/Resources/Kernels/default.metallib", "original")
        self.write(".gitignore", ".build/\n")
        for name, body in (
            ("xcrun", XCRUN),
            ("xcodebuild", '#!/usr/bin/env bash\necho "Xcode 27.0 (mock)"\n'),
        ):
            path = self.bin / name
            path.write_text(body, encoding="utf-8")
            path.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("MOCK_", "ASKI_", "GIT_"))
        }
        self.env.update(
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            TMPDIR=str(self.tmp),
            MOCK_LOG=str(self.home / "commands.log"),
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL=os.devnull,
        )
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Infra Test", "-c", "user.email=infra@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")

    def write(self, path, contents):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
        return target

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], env=self.env,
                              check=True, capture_output=True, text=True, timeout=10)

    def command(self, script, *args):
        return ["bash", str(self.repo / "Scripts" / script), *args]

    def run_script(self, script, *args, expected=0, cwd=None, **env):
        result = subprocess.run(self.command(script, *args), cwd=cwd or self.repo,
                                env={**self.env, **env}, capture_output=True,
                                text=True, timeout=15)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def doctor(self, *args, **kwargs):
        return self.run_script("repo-doctor.sh", *args, **kwargs)

    def docc(self, *args, **kwargs):
        return self.run_script("validate-docc.sh", *args, **kwargs)

    def commands(self):
        log = Path(self.env["MOCK_LOG"])
        return log.read_text() if log.exists() else ""

    def assert_clean_tmp(self):
        self.assertEqual(list(self.tmp.iterdir()), [])

    def spawn(self, script, *args, **env):
        process = subprocess.Popen(self.command(script, *args), cwd=self.repo,
                                   env={**self.env, **env}, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True,
                                   start_new_session=True)
        def stop():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.communicate(timeout=10)
        self.addCleanup(stop)
        return process

    def wait_for(self, path, process):
        deadline = time.monotonic() + 10
        while not path.exists():
            if process.poll() is not None:
                self.fail(process.communicate()[0])
            if time.monotonic() > deadline:
                self.fail("mock command did not reach the rendezvous")
            time.sleep(0.02)

    def test_help_has_no_side_effects(self):
        self.assertIn("Usage:", self.doctor("--help"))
        self.assertIn("Usage:", self.docc("--help"))
        self.assertEqual(self.commands(), "")
        self.assert_clean_tmp()
        self.assertFalse((self.repo / ".build").exists())

    def test_doctor_rejects_invalid_selectors_before_running_checks(self):
        for args in (("--check",), ("--skip",), ("--check", "typo"),
                     ("--skip", "typo"), ("--check", "dirty", "--skip", "typo")):
            with self.subTest(args=args):
                self.doctor(*args, expected=64)
        self.assertEqual(self.commands(), "")
        self.assert_clean_tmp()

    def test_toolchain_minimum_and_override(self):
        for version, minimum, status in (("6.3", "6.3", 0), ("6.4", "6.3.2", 0),
                                         ("6.3.1", "6.3.2", 1), ("6.2", "6.3", 1),
                                         ("7.0", "6.3", 0), ("6.4", "invalid", 1)):
            with self.subTest(version=version, minimum=minimum):
                self.doctor("--check", "toolchain", expected=status,
                            MOCK_SWIFT_VERSION=version, ASKI_REQUIRED_SWIFT_VERSION=minimum)
        self.assert_clean_tmp()

    def test_doctor_uses_its_own_checkout_not_caller_directory(self):
        self.write("Package.resolved", "dirty checkout\n")
        self.assertIn("git worktree is dirty", self.doctor("--check", "dirty", cwd=self.home, expected=1))

    def test_git_status_failure_is_not_a_clean_worktree(self):
        shutil.rmtree(self.repo / ".git")
        output = self.doctor("--check", "dirty", expected=1)
        self.assertIn("cannot read git worktree status", output)
        self.assertNotIn("PASS git worktree is clean", output)
        self.assert_clean_tmp()

    def test_package_resolve_detects_staged_lockfile_drift(self):
        self.write("Package.resolved", "changed\n")
        self.git("add", "Package.resolved")
        self.assertIn("lockfile update", self.doctor("--check", "package-resolved", expected=1))
        self.assert_clean_tmp()

    def test_package_resolve_success_failure_and_drift(self):
        self.doctor("--check", "package-resolved")
        self.assertIn("unique error", self.doctor("--check", "package-resolved", expected=1,
                                                 MOCK_RESOLVE_STATUS="1", MOCK_MESSAGE="unique error"))
        self.doctor("--check", "package-resolved", expected=1, MOCK_RESOLVE_CHANGE="1")
        self.assert_clean_tmp()

    def test_concurrent_doctors_do_not_mix_resolve_logs(self):
        release = self.home / "release"
        jobs = []
        for label in ("first-only", "second-only"):
            ready = self.home / label
            process = self.spawn("repo-doctor.sh", "--check", "package-resolved",
                                 MOCK_READY=str(ready), MOCK_RELEASE=str(release),
                                 MOCK_MESSAGE=label, MOCK_RESOLVE_STATUS="1")
            jobs.append(process)
            self.wait_for(ready, process)
        release.touch()
        first, second = [process.communicate(timeout=10)[0] for process in jobs]
        self.assertEqual([process.returncode for process in jobs], [1, 1])
        self.assertIn("first-only", first)
        self.assertNotIn("second-only", first)
        self.assertIn("second-only", second)
        self.assertNotIn("first-only", second)
        self.assert_clean_tmp()

    def test_metallib_restores_bytes_on_success_drift_and_failure(self):
        for mode, command_status, expected in (("same", "0", 0), ("changed", "0", 1),
                                               ("changed", "1", 1)):
            with self.subTest(mode=mode, command_status=command_status):
                self.doctor("--check", "metallib", expected=expected,
                            MOCK_KERNEL=mode, MOCK_KERNEL_STATUS=command_status)
                self.assertEqual((self.repo / "Sources/Aski/Resources/Kernels/default.metallib").read_text(), "original")
                self.assertFalse((self.repo / ".build/aski-metallib-check.lock").exists())
                self.assert_clean_tmp()

    def test_metallib_lock_refuses_a_second_check(self):
        lock = self.repo / ".build/aski-metallib-check.lock"
        lock.mkdir(parents=True)
        self.assertIn("already running", self.doctor("--check", "metallib", expected=1))
        self.assertTrue(lock.exists())
        self.assertNotIn("swift run BuildKernelLibrary", self.commands())
        self.assert_clean_tmp()

    def test_metallib_restores_after_termination(self):
        ready = self.home / "ready"
        process = self.spawn("repo-doctor.sh", "--check", "metallib", MOCK_KERNEL="changed",
                             MOCK_READY=str(ready), MOCK_RELEASE=str(self.home / "release"))
        self.wait_for(ready, process)
        os.killpg(process.pid, signal.SIGTERM)
        output = process.communicate(timeout=10)[0]
        self.assertEqual(process.returncode, 143, output)
        self.assertEqual((self.repo / "Sources/Aski/Resources/Kernels/default.metallib").read_text(), "original")
        self.assertFalse((self.repo / ".build/aski-metallib-check.lock").exists())
        self.assert_clean_tmp()

    def test_metallib_parent_termination_stops_child_before_restoration(self):
        for termination in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(termination=termination):
                ready = self.home / f"child-ready-{termination}"
                stopped = self.home / f"child-stopped-{termination}"
                release = self.home / f"release-{termination}"
                process = self.spawn("repo-doctor.sh", "--check", "metallib", MOCK_KERNEL="changed",
                                     MOCK_KERNEL_CHILD_READY=str(ready), MOCK_KERNEL_CHILD_STOPPED=str(stopped),
                                     MOCK_RELEASE=str(release))
                self.wait_for(ready, process)
                process.send_signal(termination)
                try:
                    output = process.communicate(timeout=3)[0]
                except subprocess.TimeoutExpired:
                    release.touch()
                    process.communicate(timeout=10)
                    self.fail("parent-only signal did not stop Metal regeneration")
                self.assertEqual(process.returncode, 128 + termination, output)
                self.assertEqual(stopped.read_text(), "stopped")
                self.assertEqual((self.repo / "Sources/Aski/Resources/Kernels/default.metallib").read_text(), "original")
                self.assertFalse((self.repo / ".build/aski-metallib-check.lock").exists())
                self.assert_clean_tmp()

    def test_docc_cold_and_warm_cache_validate_live_catalog(self):
        self.docc(cwd=self.home)
        self.assertEqual(self.commands().count("dump-symbol-graph"), 1)
        self.docc()
        self.assertEqual(self.commands().count("dump-symbol-graph"), 1)
        self.write("Sources/Aski/Aski.docc/Aski.md", "# Changed catalog\n")
        self.docc(expected=1, MOCK_DOCC_STATUS="1")
        self.assertEqual(self.commands().count("dump-symbol-graph"), 1)
        self.assertEqual(self.commands().count("--warnings-as-errors"), 3)
        self.assertNotIn("docc convert --help", self.commands())
        self.assert_clean_tmp()

    def test_source_package_and_toolchain_changes_invalidate_docc_cache(self):
        self.docc()
        for path in ("Sources/Aski/Example.swift", "Package.swift", "Package.resolved"):
            self.write(path, (self.repo / path).read_text() + "\n")
            self.docc()
        self.docc(MOCK_SWIFT_VERSION="6.4.1")
        self.assertEqual(self.commands().count("dump-symbol-graph"), 5)
        self.assert_clean_tmp()

    def test_docc_toolchain_discovery_failure_does_not_populate_cache(self):
        for env in ({"MOCK_SWIFT_STATUS": "1"}, {"MOCK_SDK_STATUS": "1"}):
            with self.subTest(env=env):
                self.docc(expected=1, **env)
                self.assertFalse((self.repo / ".build/aski-docc-symbols-cache/Aski.symbols.key").exists())
                self.assertFalse((self.repo / ".build/aski-docc.lock").exists())
                self.assert_clean_tmp()
        self.assertNotIn("dump-symbol-graph", self.commands())

    def test_interrupted_cache_publication_cannot_pair_new_graph_with_old_key(self):
        self.docc()
        self.write("Sources/Aski/Example.swift", "public struct Changed {}\n")
        real_mv = shutil.which("mv")
        self.assertIsNotNone(real_mv)
        fake_mv = self.bin / "mv"
        fake_mv.write_text(
            '#!/usr/bin/env bash\n'
            'case "$1" in *.key.tmp) exit 1 ;; esac\n'
            'exec "' + real_mv + '" "$@"\n'
        )
        fake_mv.chmod(0o755)
        self.docc(expected=1)
        self.assertFalse((self.repo / ".build/aski-docc-symbols-cache/Aski.symbols.key").exists())
        fake_mv.unlink()
        self.docc()
        self.assertEqual(self.commands().count("dump-symbol-graph"), 3)
        self.assert_clean_tmp()

    def test_stale_graph_cannot_hide_failed_extraction(self):
        self.write(".build/mock/symbolgraph/Aski.symbols.json", "stale")
        self.assertIn("missing/empty", self.docc(expected=1, MOCK_MISSING_GRAPH="1"))
        self.assertNotIn("docc convert", self.commands())
        self.assert_clean_tmp()

    def test_docc_rejects_invalid_output_options_without_side_effects(self):
        for args in (("--output-dir",), ("--output-dir", "--emit-markdown"),
                     ("--output-dir", "result"), ("--unknown",)):
            with self.subTest(args=args):
                self.docc(*args, expected=64)
        self.assertEqual(self.commands(), "")
        self.assert_clean_tmp()

    def test_docc_refuses_existing_output_and_symlinks(self):
        existing = self.home / "existing"
        existing.mkdir()
        marker = existing / "important.txt"
        marker.write_text("keep")
        dangling = self.home / "dangling"
        dangling.symlink_to(self.home / "missing")
        for path in (existing, dangling):
            self.docc("--emit-markdown", "--output-dir", str(path), expected=64)
        self.assertEqual(marker.read_text(), "keep")
        self.assertTrue(dangling.is_symlink())
        self.assertEqual(self.commands(), "")

    def test_markdown_explicit_output_is_relative_to_caller_and_survives_validation(self):
        output = self.docc("--emit-markdown", "--output-dir", "release output", cwd=self.home)
        directory = self.home / "release output"
        self.assertIn(str(directory), output)
        self.assertTrue((directory / "mock-artifact.txt").exists())
        self.docc()
        self.assertTrue((directory / "mock-artifact.txt").exists())
        self.assert_clean_tmp()

    def test_markdown_default_outputs_are_unique_and_retained(self):
        paths = []
        for _ in range(2):
            output = self.docc("--emit-markdown")
            paths.append(Path(output.split("DocC Markdown output: ", 1)[1].strip()))
        self.assertNotEqual(*paths)
        for path in paths:
            self.assertTrue((path / "mock-artifact.txt").exists())
            self.assertEqual(list(path.parent.iterdir()), [path])
        self.docc()
        self.assertTrue(all(path.exists() for path in paths))

    def test_markdown_failures_remove_only_owned_output(self):
        directory = self.home / "output"
        for env in ({"MOCK_MARKDOWN_STATUS": "1"}, {"MOCK_MISSING_MANIFEST_FLAG": "1"},
                    {"MOCK_DOCC_STATUS": "1"}):
            with self.subTest(env=env):
                self.docc("--emit-markdown", "--output-dir", str(directory), expected=1, **env)
                self.assertFalse(directory.exists())
                self.assert_clean_tmp()

    def test_docc_lock_refuses_concurrent_validation_and_recovers(self):
        ready, release = self.home / "ready", self.home / "release"
        process = self.spawn("validate-docc.sh", MOCK_READY=str(ready), MOCK_RELEASE=str(release))
        self.wait_for(ready, process)
        self.assertIn("another validation", self.docc(expected=1))
        self.assertTrue((self.repo / ".build/aski-docc.lock").exists())
        release.touch()
        output = process.communicate(timeout=10)[0]
        self.assertEqual(process.returncode, 0, output)
        self.assertFalse((self.repo / ".build/aski-docc.lock").exists())
        self.docc()
        self.assert_clean_tmp()

    def test_docc_termination_cleans_output_and_lock(self):
        ready = self.home / "ready"
        directory = self.home / "output"
        process = self.spawn("validate-docc.sh", "--emit-markdown", "--output-dir", str(directory),
                             MOCK_READY=str(ready), MOCK_RELEASE=str(self.home / "release"))
        self.wait_for(ready, process)
        os.killpg(process.pid, signal.SIGTERM)
        output = process.communicate(timeout=10)[0]
        self.assertEqual(process.returncode, 143, output)
        self.assertFalse(directory.exists())
        self.assertFalse((self.repo / ".build/aski-docc.lock").exists())
        self.assert_clean_tmp()

    def test_invalid_tmpdir_fails_before_apple_tool_execution(self):
        for script in ("repo-doctor.sh", "validate-docc.sh"):
            with self.subTest(script=script):
                args = ("--check", "toolchain") if script == "repo-doctor.sh" else ()
                self.run_script(script, *args, expected=1, TMPDIR=str(self.home / "missing"))
        self.assertEqual(self.commands(), "")
        self.assertFalse((self.repo / ".build/aski-docc.lock").exists())


if __name__ == "__main__":
    unittest.main()
