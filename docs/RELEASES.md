# Release builds and disk images

The project provides a local Release build command and a GitHub Actions workflow. A DMG contains `Antena.app`, an `Applications` shortcut and English/Spanish/French installation instructions. Installation is drag-and-drop; no privileged package installer or kernel extension is installed.

## Local build

Prepare the pinned VideoLAN dependency and the exact firmware described in [firmware provenance](../firmware/PROVENANCE.md), then run:

```sh
./script/build_release.sh
```

The version defaults to the repository's `VERSION` file. To override it and its numeric build number:

```sh
APP_VERSION=0.1.0 APP_BUILD_NUMBER=1 ./script/build_release.sh
```

Outputs:

- `dist/Antena-<version>-arm64.dmg`
- `dist/Antena-<version>-arm64.dmg.sha256`
- `build/release-build.log` and `build/release-package.log`

The script requires Apple Silicon and the macOS 27 SDK. It builds the **Release** configuration, disables debug dylib injection, validates all runtime dependencies, signs the copied bundle, creates a compressed image and mounts it read-only to verify the app signature and installation shortcut. It does not start capture or need the USB tuner.

The native packager is also available independently:

```sh
./script/antena_tools.sh package-dmg /absolute/path/Antena.app
```

`SIGNING_IDENTITY` optionally selects an already available signing identity. The default is `-` (ad hoc). A non-ad-hoc identity enables secure timestamps and hardened-runtime signing for the packaged code. Providing a certificate does not itself notarize the result; see the distribution notes below.

## GitHub Actions

Workflow: [release-dmg.yml](../.github/workflows/release-dmg.yml).

It runs manually from **Actions → Build release DMG → Run workflow**, or on version tags matching `v…`. A tag must contain a numeric version, such as `v0.1.0`. Manual runs can use `VERSION` or an explicit version input.

The workflow uses GitHub's **`xcode-27` arm64 runner**, verifies that the selected macOS SDK is 27 or newer, prepares the pinned VideoLAN runtime, runs offline model/tool/transport tests, and builds/verifies the DMG. See the official [runner reference](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).

### Required firmware secret

In **Settings → Secrets and variables → Actions**, create a repository secret named **`XC3028_FIRMWARE_BASE64`**, containing the base64 encoding of the exact firmware you acquired separately. On macOS, the following copies that encoding to your clipboard without printing it in the terminal:

```sh
base64 -i firmware/xc3028-v27.fw | pbcopy
```

The workflow restores the file with restricted permissions and validates its structure and pinned SHA-256 before using it. The value is not printed or included as a separate build artifact. Missing or incorrect firmware stops the workflow with an explicit error. The resulting application embeds firmware as the current app build requires, so distribute such a DMG only when you have the necessary redistribution rights. Using a secret does not grant those rights.

Code and binary dependencies are separate: the source ZIP/repository continue to exclude the firmware and downloaded VideoLAN binaries. The DMG intentionally includes the verified runtime needed to run the app. Existing license and provenance notices are retained inside the app bundle.

### Retrieve the output

After a successful run, download **`Antena-macOS27-arm64-<run number>`** from the run's **Artifacts** section. It contains the DMG and SHA-256 file. Artifact retention is 14 days. Failure logs are retained for 7 days.

This workflow has read-only repository permission, pins external actions by commit and does not automatically create or publish GitHub Releases. You can review the artifact and attach it to a release yourself. There is no remote workflow run until these files are pushed to your GitHub repository and the required secret is configured.

## Signing and notarization status

The default artifact is **ad hoc signed and not notarized by Apple**. Creating a DMG does not change that trust status. For a broadly distributed release, use a valid Developer ID Application identity and complete Apple's notarization process before publishing. Certificate import, keychain provisioning, notarization submission and account credentials are not configured by the default workflow.

The package signature and mounted disk image are validated locally, but that does not mean Gatekeeper will accept an Internet-downloaded ad hoc package without additional user interaction. See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## About window

**Antena → About Antena** displays the running app's version/build, **Luigimonsoft**, [the author profile](https://github.com/luigimonsoft), the project date **October 23, 2026**, platform and component credits. These values live in `Antena/Support/ProjectInfo.swift`; user-facing labels are translated into English, Spanish and French.
