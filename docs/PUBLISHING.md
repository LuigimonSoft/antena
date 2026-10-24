# Public source preparation

The public repository contains source code, tests, build scripts, the generated Xcode project and shared scheme, icons and attributed station logos, documentation and license notices. English is the default README; Spanish and French versions are linked from it.

## Validate and export

From the repository root, with Git and Swift available:

```sh
./script/antena_tools.sh prepare-github --check
./script/antena_tools.sh prepare-github
```

The first command validates the source boundary without writing an archive. The second creates `dist/Antena-source.zip` and `dist/github-manifest.txt`. The archive contains a clean `Antena-source/` folder. No Git repository is initialized in the working project, no commit is created and nothing is uploaded.

The exporter evaluates `.gitignore` using a temporary Git index, checks required files, rejects unexpected top-level files, symlinks and workstation-specific user/volume paths in text files, and exercises representative exclusion rules. If a repository already exists in the project root, it also reports tracked files that fall outside the public-source rules. It is a source-boundary check, not a comprehensive secret scanner; review the generated manifest and source before publishing.

## Excluded local content

- Agent configuration and instruction files, editor workspace settings and local recovery notes.
- Build products, distribution archives, reports, logs and recordings.
- Downloaded VideoLAN runtime and extracted firmware binaries/work directories.
- Xcode user state, macOS AppleDouble files and tool caches.
- Local environment files and signing credentials covered by `.gitignore`.

These files stay available locally when needed; ignoring them does not delete them. The public Xcode project does not reference the local recovery note. `.gitattributes` also excludes local working material from `git archive` exports.

## Dependencies and assets

A new checkout requires `./script/bootstrap_vlc.sh` and the exact locally supplied firmware documented in [PROVENANCE.md](../firmware/PROVENANCE.md). Do not add those binaries to the source repository. Keep [LICENSE](../LICENSE), upstream reference notices and [logo attribution](channel-logo-sources.json) with the source.

The source archive is not a compiled or notarized application release. Existing application archives in `dist/` are local outputs and are excluded from the public source set.

## Before pushing an existing repository

`.gitignore` does not untrack files already committed or staged. Inspect `git status` and `git ls-files`, run the validation command and review the manifest. If private files were previously committed, adding ignore rules does not remove them from history; resolve that separately before making the repository public.
