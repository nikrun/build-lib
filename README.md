<p align="left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://nikrun.dev/brand/nikrun-lockup-dark-mono.svg">
    <img alt="Nikrun" src="https://nikrun.dev/brand/nikrun-lockup-light.svg" height="52">
  </picture>
</p>

# Nikrun Build Library

[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](./LICENSE)
[![Website: nikrun.dev](https://img.shields.io/badge/website-nikrun.dev-0b0e14)](https://nikrun.dev)

> **Shared PowerShell build, packaging, CycloneDX SBOM, and release automation for Nikrun repositories.**

[nikrun.dev](https://nikrun.dev) · [`nik` CLI](https://github.com/nikrun/cli) · [Free Pascal SDKs](https://github.com/nikrun/sdk) · [VS Code Extension](https://github.com/nikrun/vscode) · [Website & Docs](https://github.com/nikrun/web) · [Brand Assets](https://github.com/nikrun/brand) · **[Build Library](https://github.com/nikrun/build-lib)**

---

**Nikrun Build Library** centralizes cross-platform versioning, Keep-a-Changelog release-note generation, SHA-256 release manifests, archive packaging, SBOM generation, and post-release version bump automation across the **Nikrun** ecosystem.

It is consumed as a Git submodule (`build-lib/`) in [`nikrun/cli`](https://github.com/nikrun/cli) and [`nikrun/vscode`](https://github.com/nikrun/vscode).

---

## Overview

- **Shared PowerShell Module (`ps-modules/Common/`):** Imported by each repository's `build.ps1`:
  - `Resolve-BuildVersion` — Resolves `CleanVersion` (`X.Y.Z`) and `VersionTag` (`vX.Y.Z-build.N-channel.<dev|insider|stable>`) from `version.txt` or `-Version`.
  - `New-ReleaseNotesSpec` & `New-ReleaseNotesMarkdown` — Parses `changelog.yml` into `<product>-<versionTag>-release-notes.json` and formatted GitHub Release Markdown notes.
  - `New-Manifest` — Generates `manifest.json` describing product downloads, file sizes, SHA-256 checksums, and release metadata.
  - `New-ZipArchive` & `Get-FileSha256` — Cross-platform `.zip` packaging (preserving Unix executable permissions) and SHA-256 digest calculation.
  - `New-NpmCycloneDxSbom` — Generates CycloneDX JSON SBOMs (`*-sbom.cdx.json`) enriched with `package-lock.json` integrity hashes.
  - `Invoke-BuildLibTests` — Runs the Pester 5+ unit test suite (`Common.Tests.ps1`).
- **Composite GitHub Action (`github-actions/bump-version/`):** Increments `version.txt` (`patch`, `minor`, `major`), stamps the release date and next version section into `changelog.yml` (and `package.json` when present), and opens a Pull Request against `main` after `stable` releases.

---

## Quick Start

Run the Pester 5+ unit test suite directly from PowerShell (`pwsh` 7+ or Windows PowerShell):

```powershell
Import-Module .\ps-modules\Common\Common.psd1 -Force
Invoke-BuildLibTests
```

---

## Repository Structure

```text
build-lib/
├── github-actions/
│   └── bump-version/
│       └── action.yml             # Post-release SemVer & changelog bump composite action
└── ps-modules/
    └── Common/
        ├── Common.psd1            # PowerShell module manifest
        ├── Common.psm1            # Versioning, changelog, manifest, archive & SBOM functions
        └── Common.Tests.ps1       # Pester 5+ unit test suite
```

---

## License

Copyright (c) 2026 The Nikrun Contributors.

Licensed under the **GNU General Public License v3.0 or later** (`GPL-3.0-or-later`) — see [LICENSE](./LICENSE).
