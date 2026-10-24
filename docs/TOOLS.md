# Native development tools

All project-maintained development tools use Swift and macOS system utilities. No additional language interpreter or third-party Swift package is required. The app remains Swift/AppKit/SwiftUI with its existing C driver and C bridge to libVLC.

## Entry point

```sh
./script/antena_tools.sh --help
```

The Bash launcher builds `script/Tools/*.swift` with Xcode's `swiftc` when the cached executable is missing or a source file is newer. The executable and compiler module cache live under the ignored `build/tools/` directory. Subsequent calls reuse the executable. The launcher changes to the project root, so it can be invoked from another working directory.

| Command | Purpose |
| --- | --- |
| `verify-firmware [FILE]` | Validate container structure, all 80 image boundaries and the pinned SHA-256 using CryptoKit |
| `inspect-ts FILE` | Stream through a transport recording and print JSON describing PAT, PMT, ATSC VCT and section CRC results |
| `generate-project` | Regenerate the Xcode project and shared scheme with stable SHA-1-derived object identifiers |
| `stage-app APP` | Validate bundle identity, copy without AppleDouble metadata, preserve runtime symlinks, sign and verify the APFS bundle |
| `prepare-github --check` | Check public source inclusion and ignore rules without creating an archive |
| `prepare-github` | Validate and export the clean source ZIP and manifest |
| `self-test` | Run tooling regression tests without using the USB tuner |

```sh
./script/antena_tools.sh verify-firmware
./script/antena_tools.sh inspect-ts recordings/sample.ts
./script/antena_tools.sh generate-project
./script/antena_tools.sh prepare-github --check
./script/antena_tools.sh self-test
```

Replace the recording example with an existing file. Firmware validation and `self-test` require the exact local firmware described in [provenance](../firmware/PROVENANCE.md). `make test` invokes the Swift firmware validator as well as the C transport tests.

## Implementation

- `Support.swift`: process execution, temporary directories and file helpers.
- `Firmware.swift`: bounded container parsing and SHA-256 validation.
- `TransportInspector.swift`: packet/section assembly, MPEG CRC, PAT/PMT and virtual channel tables.
- `ProjectGenerator.swift`: deterministic Xcode project and shared scheme generation.
- `AppStager.swift`: identity checks, clean bundle copying, ad hoc signing and signature verification.
- `SourceExporter.swift`: temporary Git index, public file validation, clean source staging and ZIP export using macOS `ditto`.
- `SelfTest.swift`: corruption, parsing, filesystem and generation regressions.
- `main.swift`: command dispatch, argument validation and error reporting.

The transport inspector reads recordings in chunks rather than loading the whole video into memory. It exits unsuccessfully for invalid packet boundaries or missing complete PAT/PMT tables; CRC/transport error counts are included in its JSON report. It is an inspection tool, not a media decoder or a replacement for RF reception testing.

The app staging command replaces only a destination bundle with Antena's expected bundle identifier. The exporter uses a temporary Git repository and does not create commits or upload source. Its ZIP contains only the validated source manifest; generated executables, firmware, dependencies and workspace settings stay excluded.

## Regression tests

`self-test` checks the valid firmware, truncation, altered checksums and trailing bytes; a known MPEG CRC vector, PAT/PMT extraction, duplicate packets and malformed input; clean copying and symlink preservation; deterministic project generation; and public-source rules. It regenerates the project as part of this check.

For application behavior, continue using the standalone Swift tests and `make test` documented in the [README](../README.md). Changes to these tools should preserve the public-source boundary and keep the three README command examples consistent.

## Release packaging

`./script/build_release.sh` builds the Release configuration and calls the native `package-dmg APP` command. This stages the bundle on APFS, makes resources readable for installation, signs nested Mach-O code before the app, creates a compressed disk image and mounts it read-only for verification. See [release configuration](RELEASES.md), including the mandatory CI firmware secret and the ad hoc signing default.
