# CLI packaging and package documentation

This guide is for maintainers preparing a distribution candidate. The source
quickstart remains in the [README](../../README.md#try-it). Check
[Releases](https://github.com/BigCactusLabs/Aski/releases) for assets actually
published; adding packaging scripts or an index manifest does not publish them.

## Build a CLI candidate

Use a clean checkout on an Apple silicon Mac with full Xcode selected and the
package's required Swift toolchain. The candidate is an arm64-only executable, not
a universal binary; the packager refuses any other architecture. Xcode 27 runs
only on Apple silicon, and Intel Macs stop at macOS 26. Run the existing local acceptance gates on the commit you intend
to package:

```bash
just check
just release-preflight
```

Then choose a new output directory whose parent already exists:

```bash
just package-cli /tmp/aski-cli-candidate
```

The script can also be called directly:

```bash
./Scripts/package-cli.sh --output-dir /tmp/aski-cli-candidate
```

Use one invocation, with a fresh destination for each candidate. Paths containing
spaces are supported when quoted, and a relative path resolves against the
directory you run the command from. The Makefile wrapper accepts the destination as
an environment/make variable:

```bash
make package-cli ASKI_PACKAGE_OUTPUT=/tmp/aski-cli-candidate
```

The packager is separate from `just check`: it does not run the full test suite,
regenerate kernels, or perform release preflight on your behalf. It checks that
the source checkout is clean, captures its commit, and builds an immutable
`git archive` snapshot using SwiftPM's release configuration, the toolchain's
default build system (Swift Build as of Swift 6.4, where the native backend is
deprecated), and a private `--scratch-path`. Dependency resolution must use `Package.resolved`.

The ordinary `.build` directory is not used for the candidate build. This costs
a fresh build but gives the packaging smoke test a stronger isolation boundary.

## Contents and layout

On success, the new output directory contains:

- `aski-<commit-prefix>-macos-arm64.tar.gz`
- `SHA256SUMS`

The placeholder above describes the filename; it is not literal shell input.
The architecture is read from the built executable and must be `arm64`. The archive holds one
directory containing the executable, its adjacent `Aski_Aski.bundle`, project and
font license notices, and `release-info.txt`.

Keep the executable and its resource bundle together. The bundle contains the
font, character-set shape data, Metal library, and privacy manifest. Swift Build
places them under `Aski_Aski.bundle/Contents/Resources/`; the native backend used
a flat bundle, and the packager accepts either. `release-info.txt` records which
layout the candidate has. Copying only the executable is not a supported
installation layout.

Do not symlink the executable onto `PATH` either: `Bundle.module` looks for the
bundle next to the path the process was started from, so a symlinked `aski`
cannot find its resources
([swift-package-manager#8510](https://github.com/swiftlang/swift-package-manager/issues/8510)).
Use a small wrapper script that `exec`s the real executable instead.

The script checks the required resources against the source snapshot before
creating the archive. That check matters because some runtime paths can fall back
to a system font or a different rendering implementation when a resource is absent.

`release-info.txt` records the full source commit and the actual build toolchain,
OS, and architecture. Use that file to identify the candidate. The CLI's current
`--version` probes Git in the **working directory**: outside a repository it can
say `unknown`, and inside another repository it can report that repository's
commit. It is not a build-version attestation.

## Why the smoke check removes its build

SwiftPM's generated `Bundle.module` accessor first tries the bundle next to the
running executable, then an absolute bundle path from the build machine. A moved
binary can therefore appear to work while still using resources from its original
build directory.

The packager removes its private source and build directories, extracts the
archive into a separate temporary directory, and invokes that extracted CLI from
an unrelated working directory. It checks help, a bundled-image text/PNG render,
and JSON inspection. A failed resource check, build, extraction, or smoke check
does not leave a completed candidate in the requested destination.

This exercises relocation on the build Mac. It does not establish compatibility
with every supported macOS release, prove every lab/effect path, or satisfy
Gatekeeper distribution requirements. The existing native tests and a separate
fresh-machine installation check remain necessary before publishing.

Primary implementation references:

- [SwiftPM resource accessor](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift)
- [SwiftPM resource bundle naming](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageLoading/PackageBuilder.swift)
- [Aski resource declarations](../../Package.swift)

## Publication and Homebrew

The packager creates a local candidate. It does not create a tag, sign or notarize
an archive, upload a release, or modify a Homebrew formula. Do not describe its
output as a signed installer; a toolchain's ad-hoc code signature is not Developer
ID signing or notarization.

The candidate carries only the linker's ad-hoc signature. Downloaded through a
browser, the archive gets the `com.apple.quarantine` attribute and Gatekeeper
blocks the unnotarized executable. Downloads made with `curl`, and Homebrew
formula installs, are not quarantined. Until Developer ID signing and
notarization exist, point users at the formula or a `curl` download rather than
a browser link.

Before publication, record native gate results for the final commit, test the
archive on another Mac without the source checkout, choose and verify the signing
and distribution approach, and commit the matching changelog and release notes.
Keep the archive checksum paired with the exact final bytes; any packaging or
signing change requires a new checksum and validation.

The existing [BigCactusLabs tap](https://github.com/BigCactusLabs/homebrew-tap) can
consume a tested release archive later. The formula must:

- install the executable and `Aski_Aski.bundle` together under `libexec`;
- expose the command with `bin.write_exec_script libexec/"aski"`, a wrapper
  script, never a `bin` symlink (see the bundle lookup note above);
- declare the arm64-only requirement (`depends_on arch: :arm64`);
- run a `test do` block that renders an image with the installed command.

Ship it as a formula, not a cask: casks keep the quarantine attribute, so an
unnotarized executable would be blocked. Add the formula only when the release
URL and checksum are real. No `brew install` command is promised by this guide.

## Swift Package Index documentation

The root [`.spi.yml`](../../.spi.yml) opts the `Aski` library target into hosted
DocC generation:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [Aski]
```

No explicit platform or Swift version override is set, so SPI picks its default
documentation build environment. No additional package dependency is needed; SPI
injects the DocC plugin when necessary.

This file configures processing **after the package is indexed**, so it has no
effect until Aski is submitted to SPI. It does not submit Aski, create a working
documentation URL, or prove the documentation build passes; merging it without a
submission changes nothing. Follow the [package inclusion requirements](https://swiftpackageindex.com/add-a-package),
then verify the published package page and DocC output before adding badges or a
homepage link. SPI's current instructions say default-branch configuration changes
can take up to 24 hours to be processed once indexed.

See SPI's [official configuration guide](https://github.com/SwiftPackageIndex/SPIManifest/blob/e67725f6ce2ad599f725bc5ec7d45ecbfefaedad/Sources/SPIManifest/Documentation.docc/CommonUseCases.md).

## Verification of packaging changes

`just test-infra` includes portable packaging tests using fake Apple commands in
temporary Git checkouts. They exercise archive contents, relocation checks,
failure cleanup, destination handling, and protection of the normal build tree.
They do not compile Swift or render an image with Aski.

Run those tests when changing the packager, then run the native gate and candidate
build above on a Mac. A passing portable test is not a release artifact.
