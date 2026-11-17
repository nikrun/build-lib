#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'Common.psd1')

    function Read-Manifest([string]$Dir) {
        return Get-Content (Join-Path $Dir 'manifest.json') -Raw | ConvertFrom-Json
    }

    $script:downloads = [ordered]@{
        'x86_64-win64' = [ordered]@{
            url    = 'nik-v0.1.0-build.0-channel.dev-x86_64-win64.zip'
            size   = 1024
            sha256 = ('a' * 64)
        }
    }
}

Describe 'Resolve-BuildVersion' {
    It 'reads version.txt and constructs dev channel VersionTag when -Version is omitted' {
        $dir = Join-Path $TestDrive 'ver-default'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'version.txt') -Value "0.1.0`n" -NoNewline

        $res = Resolve-BuildVersion -RootDir $dir
        $res.CleanVersion | Should -Be '0.1.0'
        $res.VersionTag | Should -Be 'v0.1.0-build.0-channel.dev'
    }

    It 'parses explicit -Version tag into VersionTag and CleanVersion' {
        $dir = Join-Path $TestDrive 'ver-explicit'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $res = Resolve-BuildVersion -RootDir $dir -Version 'v1.2.3-build.42-channel.insider'
        $res.CleanVersion | Should -Be '1.2.3'
        $res.VersionTag | Should -Be 'v1.2.3-build.42-channel.insider'
    }
}

Describe 'New-ReleaseNotesSpec & New-ReleaseNotesMarkdown' {
    It 'parses changelog.yml into JSON spec and Markdown notes ignoring date metadata' {
        $dir = Join-Path $TestDrive 'notes-test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $clPath = Join-Path $dir 'changelog.yml'
        @"
changelog:
  - version: 0.2.0
    changes:
      added: []
      fixed: []
  - version: 0.1.0
    date: '2026-11-17'
    changes:
      added:
        - 'Initial CLI release'
      fixed:
        - 'Fix edge case in ''nik lsp'''
      removed: []
"@ | Set-Content -Path $clPath -Encoding UTF8

        $jsonFile = New-ReleaseNotesSpec -ChangelogPath $clPath -CleanVersion '0.1.0' -ProductKey 'nik' -VersionTag 'v0.1.0-build.5-channel.stable' -OutDir $dir
        $jsonFile | Should -Be 'nik-v0.1.0-build.5-channel.stable-release-notes.json'
        $parsed = Get-Content (Join-Path $dir $jsonFile) -Raw | ConvertFrom-Json
        $parsed.added[0] | Should -Be 'Initial CLI release'
        $parsed.fixed[0] | Should -Be "Fix edge case in 'nik lsp'"

        $mdPath = Join-Path $dir 'release-notes.md'
        New-ReleaseNotesMarkdown -ChangelogPath $clPath -CleanVersion '0.1.0' -ProductName 'Nikrun CLI' -VersionTag 'v0.1.0-build.5-channel.stable' -OutputPath $mdPath | Out-Null
        $md = Get-Content $mdPath -Raw
        $md | Should -Match '### Added'
        $md | Should -Match 'Initial CLI release'
        $md | Should -Not -Match '### Removed'
    }
}

Describe 'New-Manifest' {
    It 'omits "specs" and "sdks" when both are empty' {
        $dir = Join-Path $TestDrive 'm1'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Manifest -ProductKey nik -ProductName 'Nikrun CLI' -VersionTag v1 -OutDir $dir -Downloads $script:downloads | Out-Null
        $product = (Read-Manifest $dir).nik
        $product.PSObject.Properties.Name | Should -Not -Contain 'specs'
        $product.PSObject.Properties.Name | Should -Not -Contain 'sdks'
        $product.downloads.'x86_64-win64'.url | Should -Be 'nik-v0.1.0-build.0-channel.dev-x86_64-win64.zip'
    }

    It 'omits "specs" when it only contains an empty nested table' {
        $dir = Join-Path $TestDrive 'm2'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $specs = [ordered]@{ sbom = [ordered]@{} }
        New-Manifest -ProductKey nik -ProductName 'Nikrun CLI' -VersionTag v1 -OutDir $dir -Downloads $script:downloads -Specs $specs | Out-Null
        (Read-Manifest $dir).nik.PSObject.Properties.Name | Should -Not -Contain 'specs'
    }

    It 'keeps populated specs and prunes empty nested entries' {
        $dir = Join-Path $TestDrive 'm3'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $specs = [ordered]@{
            'release-notes' = 'nik-v1-release-notes.json'
            empty           = [ordered]@{}
        }
        New-Manifest -ProductKey nik -ProductName 'Nikrun CLI' -VersionTag v1 -OutDir $dir -Downloads $script:downloads -Specs $specs | Out-Null
        $product = (Read-Manifest $dir).nik
        $product.specs.'release-notes' | Should -Be 'nik-v1-release-notes.json'
        $product.specs.PSObject.Properties.Name | Should -Not -Contain 'empty'
    }
}

Describe 'New-ZipArchive & Get-FileSha256' {
    It 'creates a root-level zip archive and computes lowercase SHA-256 without sidecar files' {
        $dir = Join-Path $TestDrive 'zip-test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $dummyBin = Join-Path $dir 'nik.exe'
        Set-Content -Path $dummyBin -Value 'dummy-binary-payload' -Encoding ASCII

        $zipPath = Join-Path $dir 'nik-v0.1.0-x86_64-win64.zip'
        New-ZipArchive -SourceFiles @($dummyBin) -DestinationZipPath $zipPath | Out-Null
        Test-Path $zipPath | Should -BeTrue

        $sha = Get-FileSha256 -FilePath $zipPath
        $sha | Should -Match '^[0-9a-f]{64}$'
        Test-Path "$zipPath.sha256" | Should -BeFalse
    }
}
