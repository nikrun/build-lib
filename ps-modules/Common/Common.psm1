function Write-Utf8NoBom {
    param (
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertFrom-ChangelogYml {
    <#
    .SYNOPSIS
    Parses a Nikrun changelog.yml and returns the Keep-a-Changelog-style
    category ordered dictionary for one version (falls back to the first/latest
    entry if the requested version isn't found). Private helper, not exported.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$ChangelogPath,
        [Parameter(Mandatory)] [string]$CleanVersion
    )

    $changesObj = [ordered]@{}
    if (-not (Test-Path $ChangelogPath)) {
        return $changesObj
    }

    $lines = Get-Content -Path $ChangelogPath -Encoding UTF8
    $currentCategory = ""
    $versions = @()
    $currentVersion = $null

    foreach ($line in $lines) {
        if ($line -match "^\s*-\s*version:\s*(.+)") {
            $currentVersion = @{
                Version = ($matches[1].Trim().Trim("'").Trim('"') -replace '^v', '')
                Changes = [ordered]@{}
            }
            $versions += $currentVersion
            $currentCategory = ""
        } elseif ($null -ne $currentVersion) {
            if ($line -match "^\s*date:\s*(.+)") {
                continue
            } elseif ($line -match "^\s*([a-zA-Z0-9_]+):\s*$") {
                if ($matches[1] -ne "changes") {
                    $currentCategory = $matches[1]
                    $currentVersion.Changes[$currentCategory] = @()
                }
            } elseif ($line -match "^\s*([a-zA-Z0-9_]+):\s*\[\]\s*$") {
                $currentCategory = $matches[1]
                $currentVersion.Changes[$currentCategory] = @()
            } elseif ($line -match "^\s*-\s*(.+)") {
                if ($currentCategory) {
                    $val = $matches[1].Trim()
                    if ($val.StartsWith("'") -and $val.EndsWith("'")) {
                        $val = $val.Substring(1, $val.Length - 2).Replace("''", "'")
                    } elseif ($val.StartsWith('"') -and $val.EndsWith('"')) {
                        $val = $val.Substring(1, $val.Length - 2)
                    }
                    $currentVersion.Changes[$currentCategory] += $val
                }
            }
        }
    }

    $target = $null
    foreach ($v in $versions) {
        if ($v.Version -eq $CleanVersion) {
            $target = $v
            break
        }
    }
    if ($null -eq $target -and $versions.Count -gt 0) {
        $target = $versions[0]
    }

    if ($target) {
        $changesObj = $target.Changes
    }

    return $changesObj
}

function New-ReleaseNotesSpec {
    <#
    .SYNOPSIS
    Parses ChangelogPath for CleanVersion and writes
    "<ProductKey>-<VersionTag>-release-notes.json" in OutDir.
    Returns the generated file's name (not full path).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$ChangelogPath,
        [Parameter(Mandatory)] [string]$CleanVersion,
        [Parameter(Mandatory)] [string]$ProductKey,
        [Parameter(Mandatory)] [string]$VersionTag,
        [Parameter(Mandatory)] [string]$OutDir
    )

    $changesObj = ConvertFrom-ChangelogYml -ChangelogPath $ChangelogPath -CleanVersion $CleanVersion

    $releaseNotesFileName = "$ProductKey-$VersionTag-release-notes.json"
    $releaseNotesPath = Join-Path $OutDir $releaseNotesFileName
    $json = $changesObj | ConvertTo-Json -Depth 5 -Compress
    Write-Utf8NoBom -Path $releaseNotesPath -Content "$json`n"

    return $releaseNotesFileName
}

function New-ReleaseNotesMarkdown {
    <#
    .SYNOPSIS
    Formats ChangelogPath for CleanVersion as GitHub-flavored Markdown and writes
    it to OutputPath. Returns OutputPath.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$ChangelogPath,
        [Parameter(Mandatory)] [string]$CleanVersion,
        [Parameter(Mandatory)] [string]$ProductName,
        [Parameter(Mandatory)] [string]$VersionTag,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    $changesObj = ConvertFrom-ChangelogYml -ChangelogPath $ChangelogPath -CleanVersion $CleanVersion
    $titles = [ordered]@{
        added      = "Added"
        changed    = "Changed"
        deprecated = "Deprecated"
        fixed      = "Fixed"
        removed    = "Removed"
        security   = "Security"
    }

    $sections = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $changesObj.Keys) {
        $items = @($changesObj[$key])
        if ($items.Count -eq 0) { continue }
        $heading = if ($titles.Contains($key)) { $titles[$key] } else { $key }
        $bullets = ($items | ForEach-Object { "- $_" }) -join "`n"
        $sections.Add("### $heading`n`n$bullets")
    }

    $body = if ($sections.Count -gt 0) {
        ($sections -join "`n`n") + "`n"
    } else {
        "Automatically generated release.`n"
    }

    Write-Utf8NoBom -Path $OutputPath -Content $body
    return $OutputPath
}

function Remove-EmptyEntries {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [System.Collections.IDictionary]$Table
    )

    $result = [ordered]@{}
    foreach ($key in $Table.Keys) {
        $value = $Table[$key]
        if ($value -is [System.Collections.IDictionary]) {
            $value = Remove-EmptyEntries -Table $value
            if ($value.Count -eq 0) { continue }
        }
        $result[$key] = $value
    }
    return $result
}

function New-Manifest {
    <#
    .SYNOPSIS
    Writes "manifest.json" for a Nikrun product build (matching Niksphere's manifest schema).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$ProductKey,
        [Parameter(Mandatory)] [string]$ProductName,
        [Parameter(Mandatory)] [string]$VersionTag,
        [Parameter(Mandatory)] [string]$OutDir,
        [System.Collections.Specialized.OrderedDictionary]$Downloads = [ordered]@{},
        [System.Collections.Specialized.OrderedDictionary]$Specs = [ordered]@{},
        [System.Collections.Specialized.OrderedDictionary]$Sdks = [ordered]@{}
    )

    $product = [ordered]@{
        "name"         = $ProductName
        "version"      = $VersionTag
        "published_at" = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        "downloads"    = $Downloads
    }

    $prunedSpecs = Remove-EmptyEntries -Table $Specs
    if ($prunedSpecs.Count -gt 0) { $product["specs"] = $prunedSpecs }
    $prunedSdks = Remove-EmptyEntries -Table $Sdks
    if ($prunedSdks.Count -gt 0) { $product["sdks"] = $prunedSdks }

    $manifest = [ordered]@{ $ProductKey = $product }

    $manifestPath = Join-Path $OutDir "manifest.json"
    $json = $manifest | ConvertTo-Json -Depth 10
    Write-Utf8NoBom -Path $manifestPath -Content "$json`n"

    return $manifest
}

function Resolve-BuildVersion {
    <#
    .SYNOPSIS
    Resolves VersionTag (e.g. "v0.1.0-build.0-channel.dev") and CleanVersion
    (e.g. "0.1.0") from an explicit -Version or from version.txt in RootDir.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$RootDir,
        [string]$Version = ""
    )

    if (-not $Version) {
        $versionFile = Join-Path $RootDir "version.txt"
        if (-not (Test-Path $versionFile)) {
            throw "Error: version.txt not found in directory $RootDir"
        }
        $baseVersion = ((Get-Content -Path $versionFile -Raw).Trim()) -replace '^v', ''
        if ($baseVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
            throw "Error: version.txt in $RootDir must contain a valid X.Y.Z SemVer, got '$baseVersion'"
        }
        $versionTag = "v${baseVersion}-build.0-channel.dev"
        $cleanVersion = $baseVersion
    } else {
        $trimmed = $Version.Trim()
        $versionTag = if ($trimmed.StartsWith("v")) { $trimmed } else { "v$trimmed" }
        $cleanVersion = $versionTag -replace '^v', ''
        if ($cleanVersion -match "^([0-9]+\.[0-9]+\.[0-9]+)") {
            $cleanVersion = $matches[1]
        }
    }

    return [PSCustomObject]@{
        VersionTag   = $versionTag
        CleanVersion = $cleanVersion
    }
}

function Get-FileSha256 {
    <#
    .SYNOPSIS
    Computes and returns the lowercase SHA-256 hex digest of FilePath.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$FilePath
    )

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        throw "Cannot compute SHA-256: file not found at $FilePath"
    }

    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-ZipArchive {
    <#
    .SYNOPSIS
    Packages Files (staged into a clean temporary directory so archive entries sit at
    the root and preserve Unix executable permissions) into DestinationZipPath.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string[]]$SourceFiles,
        [Parameter(Mandatory)] [string]$DestinationZipPath
    )

    $isWinHost = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        [bool]$IsWindows
    } else {
        ($env:OS -match 'Windows')
    }

    $destFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationZipPath)
    $destParent = Split-Path -Parent $destFull
    if ($destParent -and -not (Test-Path $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    if (Test-Path $destFull) {
        Remove-Item -Path $destFull -Force
    }

    $stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("nikrun-zip-stage-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    try {
        $entryNames = @()
        foreach ($src in $SourceFiles) {
            if (-not (Test-Path $src -PathType Leaf)) {
                throw "Source file for ZIP archive not found: $src"
            }
            $name = [System.IO.Path]::GetFileName($src)
            $stagedFile = Join-Path $stageDir $name
            Copy-Item -Path $src -Destination $stagedFile -Force
            if ((-not $isWinHost) -and ($name -notmatch '^(LICENSE|COPYING|README)(\..+)?$') -and ($name -notmatch '\.(txt|md|json|yaml|yml)$') -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
                & chmod +x $stagedFile
            }
            $entryNames += $name
        }

        if ((-not $isWinHost) -and (Get-Command zip -ErrorAction SilentlyContinue)) {
            Push-Location $stageDir
            try {
                & zip -q $destFull @entryNames
                if ($LASTEXITCODE -ne 0) { throw "zip failed with exit code $LASTEXITCODE" }
            } finally {
                Pop-Location
            }
        } elseif ($isWinHost -and (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
            Push-Location $stageDir
            try {
                & tar.exe -a -cf $destFull @entryNames
                if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE" }
            } finally {
                Pop-Location
            }
        } else {
            $stagedPaths = $entryNames | ForEach-Object { Join-Path $stageDir $_ }
            Compress-Archive -Path $stagedPaths -DestinationPath $destFull -Force
        }
    } finally {
        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $destFull
}

function New-NpmCycloneDxSbom {
    <#
    .SYNOPSIS
    Runs "@cyclonedx/cyclonedx-npm" against FrontendDir (excluding devDependencies),
    patches main component version/purl to VersionTag, enriches component hashes from
    package-lock.json SRI integrity strings, and writes
    "<ProductKey>-<VersionTag>-sbom.cdx.json" in OutDir.
    Returns the generated file's name (not full path).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$FrontendDir,
        [Parameter(Mandatory)] [string]$ProductKey,
        [Parameter(Mandatory)] [string]$VersionTag,
        [string]$ComponentKey = "",
        [Parameter(Mandatory)] [string]$OutDir
    )

    Write-Host "  -> Generating CycloneDX SBOM$(if ($ComponentKey) { " ($ComponentKey)" })..."
    $sbomFileName = if ($ComponentKey) { "$ProductKey-$VersionTag-$ComponentKey-sbom.cdx.json" } else { "$ProductKey-$VersionTag-sbom.cdx.json" }
    $sbomPath = Join-Path $OutDir $sbomFileName

    Push-Location $FrontendDir
    try {
        npx --yes @cyclonedx/cyclonedx-npm --omit dev --ignore-npm-errors --output-file $sbomPath
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "cyclonedx-npm failed for $ProductKey$(if ($ComponentKey) { " ($ComponentKey)" })"
        }

        $patchScript = @'
const fs = require('fs');
const path = require('path');

const sbomPath = process.argv[2];
const lockPath = process.argv[3];
const versionTag = process.argv[4];

const bom = JSON.parse(fs.readFileSync(sbomPath, 'utf8'));
if (bom.metadata && bom.metadata.component) {
  const comp = bom.metadata.component;
  const origVer = comp.version || '';
  comp.version = versionTag;
  if (origVer && typeof comp.purl === 'string') {
    comp.purl = comp.purl.replace('@' + origVer, '@' + versionTag);
  }
  if (origVer && typeof comp['bom-ref'] === 'string') {
    comp['bom-ref'] = comp['bom-ref'].replace('@' + origVer, '@' + versionTag);
  }
}

const integrityMap = new Map();
if (fs.existsSync(lockPath)) {
  const lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
  const packages = lock.packages || {};
  for (const [pkgPath, pkg] of Object.entries(packages)) {
    const nmIdx = pkgPath.lastIndexOf('node_modules/');
    if (!pkg || !pkg.integrity || nmIdx < 0) continue;
    const name = pkgPath.slice(nmIdx + 'node_modules/'.length);
    integrityMap.set(`${name}@${pkg.version}`, pkg.integrity);
  }
}

const algByPrefix = { sha512: 'SHA-512', sha384: 'SHA-384', sha256: 'SHA-256', sha1: 'SHA-1' };
for (const comp of bom.components || []) {
  if (Array.isArray(comp.hashes) && comp.hashes.length > 0) continue;
  const key = comp.group ? `${comp.group}/${comp.name}@${comp.version}` : `${comp.name}@${comp.version}`;
  const integrity = integrityMap.get(key) || integrityMap.get(`${comp.name}@${comp.version}`);
  if (!integrity) continue;
  const firstToken = integrity.trim().split(/\s+/)[0];
  const dashIdx = firstToken.indexOf('-');
  if (dashIdx <= 0) continue;
  const alg = algByPrefix[firstToken.slice(0, dashIdx)];
  if (!alg) continue;
  const hex = Buffer.from(firstToken.slice(dashIdx + 1), 'base64').toString('hex');
  comp.hashes = [{ alg, content: hex }];
}

fs.writeFileSync(sbomPath, JSON.stringify(bom, null, 2) + '\n', 'utf8');
'@

        $lockPath = Join-Path $FrontendDir "package-lock.json"
        & node -e $patchScript $sbomPath $lockPath $VersionTag
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "Failed to post-process CycloneDX SBOM at $sbomPath"
        }
    } finally {
        Pop-Location
    }

    return $sbomFileName
}

function Invoke-BuildLibTests {
    <#
    .SYNOPSIS
    Runs the Pester 5+ unit tests shipped with build-lib.
    Automatically installs Pester 5+ in CI environments when missing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$RootDir,
        [string]$BuildLibDir = ""
    )

    $resolvedLibDir = if ($BuildLibDir) { $BuildLibDir } else { Join-Path $RootDir "build-lib" }
    $testsDir = Join-Path $resolvedLibDir "ps-modules"

    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -ge [version]"5.0.0" } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $pester -and $env:CI) {
        Write-Host "  -> Installing Pester 5+ for CI runner..."
        Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
        $pester = Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version -ge [version]"5.0.0" } |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if (-not $pester) {
        throw "Pester 5 or newer is required to run build-lib tests. Install with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -SkipPublisherCheck"
    }

    Import-Module $pester -Force
    $result = Invoke-Pester -Path $testsDir -PassThru -Output Minimal
    if ($result.FailedCount -gt 0 -or $result.Result -eq "Failed") {
        throw "build-lib Pester tests failed ($($result.FailedCount) failed)"
    }
}

Export-ModuleMember -Function @(
    'Resolve-BuildVersion',
    'New-ReleaseNotesSpec',
    'New-ReleaseNotesMarkdown',
    'New-Manifest',
    'Get-FileSha256',
    'New-ZipArchive',
    'New-NpmCycloneDxSbom',
    'Invoke-BuildLibTests'
)
