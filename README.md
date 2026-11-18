<p align="left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://nikrun.dev/brand/nikrun-lockup-dark-mono.svg">
    <img alt="Nikrun" src="https://nikrun.dev/brand/nikrun-lockup-light.svg" height="52">
  </picture>
</p>

# Nikrun — Shared Build & Release Library (`nikrun/build-lib`)

Shared build, packaging, and release automation library for the **Nikrun** ecosystem, consumed as a Git submodule (`build-lib/`) across:

- **[`nikrun/cli`](https://github.com/nikrun/cli)** — Standalone `nik` CLI & `nikrun-lsp-protocol`
- **[`nikrun/vscode`](https://github.com/nikrun/vscode)** — Official `vscode-nikrun` Visual Studio Code extension

## Structure

- **`ps-modules/Common/`** — Shared PowerShell module imported by each repository's `build.ps1`:
  - `Resolve-BuildVersion` — Resolves `CleanVersion` (`X.Y.Z`) and `VersionTag` (`vX.Y.Z-build.N-channel.<dev|insider|stable>`) from `version.txt` or `-Version`.
  - `New-ReleaseNotesSpec` & `New-ReleaseNotesMarkdown` — Parses `changelog.yml` into `<product>-<versionTag>-release-notes.json` and formatted GitHub Release Markdown notes.
  - `New-Manifest` — Generates `manifest.json` describing product downloads, sizes, SHA-256 checksums, and spec artifacts.
  - `New-ZipArchive` & `Get-FileSha256` — Cross-platform `.zip` packaging (preserving Unix executable permissions) and SHA-256 digest calculation for `manifest.json`.
  - `New-NpmCycloneDxSbom` — Generates CycloneDX JSON SBOMs (`*-sbom.cdx.json`) enriched with `package-lock.json` integrity hashes.
  - `Invoke-BuildLibTests` — Runs the Pester 5+ unit test suite (`Common.Tests.ps1`).
- **`github-actions/bump-version/`** — GitHub composite action that increments `version.txt` (`patch`, `minor`, `major`), stamps the release date + new version section into `changelog.yml` (and `package.json` when present), and opens a Pull Request against `main` after `stable` releases.

## License

Copyright (c) 2026 The Nikrun Contributors.

Licensed under the **GNU General Public License v3.0 or later** (`GPL-3.0-or-later`) — see [LICENSE](./LICENSE).
