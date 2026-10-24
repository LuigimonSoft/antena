# Build configuration

Run commands from the repository root. Prepare libVLC with `./script/bootstrap_vlc.sh` and provide the exact firmware described in [PROVENANCE.md](../firmware/PROVENANCE.md).

```sh
ANTENA_DERIVED_DATA="$PWD/build/Xcode" ./script/build_and_run.sh --verify
```

Open `Antena.xcodeproj` in Xcode, select the shared **Antena** scheme and **My Mac** destination. The app targets arm64 and macOS 27+. For direct Xcode builds, use an APFS DerivedData location.

## Build outputs and signing

`ANTENA_DERIVED_DATA` overrides the build-products directory. Without it, the script chooses a local build or temporary directory according to its existing filesystem handling. Generated products and caches are excluded from version control.

When staging is required, the script builds with signing disabled, copies the resulting bundle to `/private/tmp/Antena-Local/Antena.app`, removes AppleDouble sidecars from the copy and signs the application ad hoc on APFS. It verifies the signature before launching. `--verify` checks process startup, not USB reception or playback.

The staged application is temporary and can be regenerated. VideoLAN libraries, plugins, the USB helper, firmware and required notices are embedded at build time. A successful local build is not a notarized release.

## Generated Xcode project

`script/Tools/ProjectGenerator.swift` owns the project structure and build settings. Update the generator when changing them, then regenerate:

```sh
./script/antena_tools.sh generate-project
plutil -lint Antena.xcodeproj/project.pbxproj
```

The project includes native app sources, localized resources, documentation and standalone test/helper source references. Only app sources belong to the app compilation target. Workspace recovery notes and user-specific Xcode state are not published.

## Source distribution

See [PUBLISHING.md](PUBLISHING.md) for the public-source boundary and validation command. Firmware, downloaded VideoLAN binaries and application bundles are not part of the source repository.
