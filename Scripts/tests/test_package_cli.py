"""Exercise CLI archive orchestration with fake Apple tools; never build Aski.

Run with Python 3's standard library: python3 -B -m unittest discover -s Scripts/tests -v
Git, tar, file comparisons and checksums are real; each checkout and TMPDIR is private.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
SHAPES = "standard minimal blocks dots lines diagonal cross diamond mixed braille".split()

TOOL = r'''#!/usr/bin/env python3
import json, os, plistlib, shutil, signal, struct, sys, time, zlib
from pathlib import Path

name, args = Path(sys.argv[0]).name, sys.argv[1:]
event = {"tool": name, "args": args, "path": str(Path(sys.argv[0]).resolve())}
state_file = Path(os.environ["MOCK_BUILD_STATE"])
if name == "aski":
    event["private_paths_remaining"] = [p for p in json.loads(state_file.read_text()).values() if Path(p).exists()]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps(event) + "\n")

def value(flag):
    return args[args.index(flag) + 1]

def png(path, width):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", width, 1, 8, 2, 0, 0, 0)
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                          + chunk(b"IDAT", zlib.compress(b"\0" * (1 + width * 3))) + chunk(b"IEND", b""))

if name == "uname":
    assert args == ["-s"], args
    print("Darwin")
elif name == "xcodebuild":
    assert args == ["-version"], args
    print("Xcode 27.0\nBuild version mock")
elif name == "sw_vers":
    assert args == ["-productVersion"], args
    print("15.7")
elif name == "xcrun" and args == ["swift", "--version"]:
    print("Apple Swift version 6.4 (mock)")
elif name == "xcrun" and args[:2] == ["swift", "build"]:
    source, scratch = Path(value("--package-path")), Path(value("--scratch-path"))
    output = scratch / "release"
    if "--show-bin-path" in args:
        print(output)
        sys.exit(0)
    state_file.write_text(json.dumps({"source": str(source), "scratch": str(scratch)}))
    output.mkdir(parents=True)
    if os.environ.get("MOCK_READY"):
        def stop(signum, frame):
            Path(os.environ["MOCK_STOPPED"]).write_text(str(signum))
            sys.exit(128 + signum)
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signum, stop)
        Path(os.environ["MOCK_READY"]).touch()
        deadline = time.monotonic() + 10
        while not Path(os.environ["MOCK_RELEASE"]).exists() and time.monotonic() < deadline:
            time.sleep(0.02)
    if os.environ.get("MOCK_BUILD_FAIL"):
        sys.exit(23)
    shutil.copyfile(__file__, output / "aski")
    (output / "aski").chmod(0o755)
    bundle = output / "Aski_Aski.bundle"
    shutil.copytree(source / "Sources/Aski/Resources", bundle)
    shutil.copyfile(source / "Sources/Aski/PrivacyInfo.xcprivacy", bundle / "PrivacyInfo.xcprivacy")
    (bundle / "generated-extra.dat").write_text("generated bundle resource")
    font = bundle / "Fonts/CourierPrime-Regular.ttf"
    if os.environ.get("MOCK_RESOURCE_FAULT") == "missing":
        font.unlink()
    elif os.environ.get("MOCK_RESOURCE_FAULT") == "corrupt":
        font.write_text("corrupt font")
    elif os.environ.get("MOCK_RESOURCE_FAULT") == "symlink":
        font.unlink()
        font.symlink_to(source / "Sources/Aski/Resources/Fonts/CourierPrime-Regular.ttf")
elif name == "xcrun" and args[:2] == ["lipo", "-archs"]:
    print(os.environ.get("MOCK_ARCH", "arm64"))
elif name == "aski":
    assert not event["private_paths_remaining"], "smoke ran before private source/build removal"
    bundle = Path(__file__).parent / "Aski_Aski.bundle"
    assert (bundle / "generated-extra.dat").read_text() == "generated bundle resource"
    fault = os.environ.get("MOCK_SMOKE_FAULT")
    if args == ["--help"]:
        print("Usage: aski <subcommand>")
    elif args[0] == "render":
        assert Path(args[1]).read_bytes() == b"image fixture"
        if fault == "render":
            sys.exit(29)
        Path(value("--output")).write_text(" \n\t" if fault == "text" else "##.\n.##\n")
        png(value("--render-png"), 159 if fault == "width" else int(value("--width")))
        if fault == "png":
            Path(value("--render-png")).write_bytes(b"not a PNG")
    elif args[0] == "inspect":
        assert value("--format") == "json"
        data = {"schemaVersion": 1, "conversion": {"columns": int(value("--columns"))}}
        if fault == "schema":
            data["schemaVersion"] = 2
        elif fault == "missing-schema":
            del data["schemaVersion"]
        elif fault == "schema-type":
            data["schemaVersion"] = "1"
        elif fault == "columns":
            data["conversion"]["columns"] = 41
        content = plistlib.dumps(data) if fault == "xml" else json.dumps(data).encode()
        Path(value("--output")).write_bytes(b"{" if fault == "json" else content)
    else:
        raise AssertionError(args)
elif name == "sips":
    data = Path(args[-1]).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", data[16:24])
    print(f"{args[-1]}\n  pixelWidth: {width}\n  pixelHeight: {height}")
elif name == "plutil":
    content = Path(args[-1]).read_bytes()
    if "-lint" in args and content.lstrip().startswith(b"{"):
        # Real plutil -lint accepts only property lists and rejects JSON.
        print(f"{args[-1]}: (Unexpected character {{ at line 1)", file=sys.stderr)
        sys.exit(1)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        data = plistlib.loads(content)
    if "-extract" in args:
        for key in value("-extract").split("."):
            data = data[key]
        assert value("-expect") == "integer" and type(data) is int
        print(data)
else:
    raise AssertionError(f"unexpected mock tool: {name} {args}")
'''


class PackageCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aski packaging tests ")
        self.addCleanup(self.temp.cleanup)
        # Resolve /var -> /private/var on macOS; the packager canonicalizes with pwd -P.
        self.home = Path(self.temp.name).resolve()
        self.repo = self.home / "checkout with spaces"
        self.tmp = self.home / "private tmp"
        self.bin = self.home / "mock tools"
        self.output = self.home / "release output"
        for path in (self.repo / "Scripts", self.tmp, self.bin):
            path.mkdir(parents=True)
        shutil.copyfile(SCRIPTS / "package-cli.sh", self.repo / "Scripts/package-cli.sh")
        for path, content in {
            "Package.swift": "// swift-tools-version: 6.3\n",
            "Package.resolved": "{}\n", ".gitignore": ".build/\n",
            "LICENSE": "license fixture\n", "NOTICE": "notice fixture\n",
            "Sources/Aski/PrivacyInfo.xcprivacy": "<plist><dict/></plist>\n",
            "Sources/Aski/Resources/Fonts/CourierPrime-Regular.ttf": "font fixture",
            "Sources/Aski/Resources/Fonts/OFL.txt": "font license fixture\n",
            "Sources/Aski/Resources/Kernels/default.metallib": "kernel fixture",
            "Sources/Aski/Resources/ShapeData/additional-resource.bin": "extra shape fixture",
            "docs/Research/Corpus/nasa-occupancy-v1/assets/carina-cosmic-cliffs.jpg": "image fixture",
        }.items():
            self.write(path, content)
        for shape in SHAPES:
            self.write(f"Sources/Aski/Resources/ShapeData/{shape}.bin", f"{shape} fixture")
        self.write(".build/keep.txt", "developer build must survive")
        for name in ("uname", "xcrun", "xcodebuild", "sw_vers", "sips", "plutil", "swift"):
            tool = self.bin / name
            tool.write_text(TOOL, encoding="utf-8")
            tool.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("MOCK_", "ASKI_", "GIT_"))}
        self.env.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        TMPDIR=str(self.tmp), MOCK_LOG=str(self.home / "commands.jsonl"),
                        MOCK_BUILD_STATE=str(self.home / "build state.json"),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Packaging Test", "-c", "user.email=packaging@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()

    def write(self, path, content):
        path = self.repo / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], env=self.env,
                              check=True, capture_output=True, text=True, timeout=10)

    def command(self, *args):
        return ["bash", str(self.repo / "Scripts/package-cli.sh"), *args]

    def run_script(self, *args, expected=0, **env):
        result = subprocess.run(self.command(*args), cwd=self.home, env={**self.env, **env},
                                capture_output=True, text=True, timeout=60)
        if expected is None:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def package(self, expected=0, **env):
        return self.run_script("--output-dir", str(self.output), expected=expected, **env)

    def events(self, tool):
        log = Path(self.env["MOCK_LOG"])
        return [entry for line in log.read_text().splitlines()
                if (entry := json.loads(line))["tool"] == tool] if log.exists() else []

    def tearDown(self):
        self.assertEqual(list(self.tmp.iterdir()), [])
        self.assertEqual(list((self.repo / ".build").iterdir()), [self.repo / ".build/keep.txt"])
        self.assertEqual((self.repo / ".build/keep.txt").read_text(), "developer build must survive")

    def test_help_and_invalid_arguments_do_not_build(self):
        self.assertIn("Usage:", self.run_script("--help"))
        for args in ((), ("--output-dir",), ("--unknown",),
                     ("--output-dir", "one", "--output-dir", "two")):
            with self.subTest(args=args):
                self.run_script(*args, expected=64)
        self.assertFalse(self.events("xcrun"))

    def test_archive_contains_complete_relocated_product_and_matching_checksums(self):
        for arch in ("arm64", "x86_64"):
            with self.subTest(architecture=arch):
                self.output = self.home / f"release output {arch}"
                self.package(MOCK_ARCH=arch)
                stem = f"aski-{self.commit[:12]}-macos-{arch}"
                archive = self.output / f"{stem}.tar.gz"
                self.assertEqual({p.name for p in self.output.iterdir()}, {archive.name, "SHA256SUMS"})
                digest, filename = (self.output / "SHA256SUMS").read_text().split()
                self.assertEqual(filename, archive.name)
                self.assertEqual(digest, hashlib.sha256(archive.read_bytes()).hexdigest())
                unpacked = self.home / f"consumer {arch}"
                unpacked.mkdir()
                subprocess.run(["tar", "-xzf", str(archive), "-C", str(unpacked)], check=True, timeout=10)
                self.assertEqual([p.name for p in unpacked.iterdir()], [stem])
                product = unpacked / stem
                self.assertTrue(os.access(product / "aski", os.X_OK))
                for path in (self.repo / "Sources/Aski/Resources").rglob("*"):
                    if path.is_file():
                        target = product / "Aski_Aski.bundle" / path.relative_to(self.repo / "Sources/Aski/Resources")
                        self.assertEqual(target.read_bytes(), path.read_bytes())
                for source, target in (("LICENSE", "LICENSE"), ("NOTICE", "NOTICE"),
                                       ("Sources/Aski/Resources/Fonts/OFL.txt", "OFL.txt"),
                                       ("Sources/Aski/PrivacyInfo.xcprivacy", "Aski_Aski.bundle/PrivacyInfo.xcprivacy")):
                    self.assertEqual((product / target).read_bytes(), (self.repo / source).read_bytes())
                self.assertEqual((product / "Aski_Aski.bundle/generated-extra.dat").read_text(), "generated bundle resource")
                self.assertIn(self.commit, (product / "release-info.txt").read_text())
        builds = [event["args"] for event in self.events("xcrun") if event["args"][:2] == ["swift", "build"]]
        self.assertEqual(len(builds), 4)
        for args in builds:
            self.assertIn("--force-resolved-versions", args)
            for flag, value in (("--build-system", "native"), ("-c", "release"), ("--product", "aski")):
                self.assertEqual(args[args.index(flag) + 1], value)
            self.assertTrue(Path(args[args.index("--scratch-path") + 1]).is_relative_to(self.tmp))
        smoke = self.events("aski")
        self.assertEqual([event["args"][0] for event in smoke], ["--help", "render", "inspect"] * 2)
        self.assertTrue(all(not event["private_paths_remaining"] for event in smoke))
        self.assertTrue(all("/unpacked/" in event["path"] for event in smoke))

    def test_existing_output_and_symlink_are_never_overwritten(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_text("keep")
        self.package(expected=1)
        self.assertEqual(marker.read_text(), "keep")
        self.output = self.home / "dangling output"
        self.output.symlink_to(self.home / "missing destination")
        self.package(expected=1)
        self.assertTrue(self.output.is_symlink())
        self.assertFalse(self.events("xcrun"))

    def test_dirty_worktree_prevents_build(self):
        untracked = self.write("untracked.txt", "uncommitted")
        self.package(expected=1)
        untracked.unlink()
        self.write("Package.resolved", "changed lockfile")
        self.package(expected=1)
        self.assertFalse(self.events("xcrun"))
        self.assertFalse(self.output.exists())

    def test_build_failure_cleans_private_workspace(self):
        self.package(expected=1, MOCK_BUILD_FAIL="1")
        self.assertFalse(self.output.exists())
        self.assertFalse(self.events("aski"))

    def test_missing_corrupt_or_linked_resource_blocks_publication(self):
        for fault in ("missing", "corrupt", "symlink"):
            with self.subTest(fault=fault):
                self.package(expected=1, MOCK_RESOURCE_FAULT=fault)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.events("aski"))

    def test_failed_render_or_invalid_smoke_outputs_block_publication(self):
        for fault in ("render", "text", "png", "width", "json", "schema", "missing-schema",
                      "schema-type", "columns", "xml"):
            with self.subTest(fault=fault):
                self.package(expected=None, MOCK_SMOKE_FAULT=fault)
                self.assertFalse(self.output.exists())
        self.assertTrue(all(not event["private_paths_remaining"] for event in self.events("aski")))

    def test_unknown_or_multiple_architectures_cannot_be_mislabeled(self):
        for arch in ("armv7", "arm64 x86_64"):
            with self.subTest(architecture=arch):
                self.package(expected=1, MOCK_ARCH=arch)
                self.assertFalse(self.output.exists())
        self.assertFalse(self.events("aski"))

    def test_parent_interrupt_stops_build_before_cleanup(self):
        for termination in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            with self.subTest(signal=termination):
                ready, stopped, release = [self.home / f"{name}-{termination}" for name in ("ready", "stopped", "release")]
                env = {**self.env, "MOCK_READY": str(ready), "MOCK_STOPPED": str(stopped), "MOCK_RELEASE": str(release)}
                process = subprocess.Popen(self.command("--output-dir", str(self.output)), cwd=self.home,
                                           env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                           text=True, start_new_session=True)
                try:
                    deadline = time.monotonic() + 10
                    while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                        time.sleep(0.02)
                    self.assertTrue(ready.exists(), "mock build did not start")
                    process.send_signal(termination)
                    output = process.communicate(timeout=3)[0]
                    self.assertEqual(process.returncode, 128 + termination, output)
                    self.assertTrue(stopped.exists(), "build was not stopped before cleanup")
                    self.assertFalse(self.output.exists())
                    self.assertEqual(list(self.tmp.iterdir()), [])
                finally:
                    release.touch()
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.communicate(timeout=10)


if __name__ == "__main__":
    unittest.main()
