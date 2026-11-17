@{
    RootModule        = 'Common.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8a9e4c31-5b14-4d9f-9f61-42c19d70e8b2'
    Author            = 'Nikrun Contributors'
    Description       = 'Shared build and release helpers (version resolution, changelog parsing, release notes, manifest generation, ZIP/SHA-256 packaging, and CycloneDX SBOM generation) for Nikrun repositories.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Resolve-BuildVersion',
        'New-ReleaseNotesSpec',
        'New-ReleaseNotesMarkdown',
        'New-Manifest',
        'Get-FileSha256',
        'New-ZipArchive',
        'New-NpmCycloneDxSbom',
        'Invoke-BuildLibTests'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
