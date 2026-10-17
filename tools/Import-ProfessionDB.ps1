param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedSha256 = '909CB41720CF6BF6920F1C25C644F89B39AD63087F589C07737E7DA943C52379',
    [string]$SourceUrl = 'https://www.curseforge.com/wow/addons/libprofessiondb/files/9095167',
    [switch]$Update,
    [switch]$CheckOnly,
    [string]$AddonRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'HordeEternal'),
    [string]$BackupRoot = (Join-Path $env:TEMP 'HordeEternal-library-backups'),
    [string]$MoonSharpPath = (Join-Path $env:TEMP 'HordeEternal-LuaTests\lib\net40-client\MoonSharp.Interpreter.dll')
)

$ErrorActionPreference = 'Stop'
if ($Update -and (-not $PSBoundParameters.ContainsKey('ExpectedSha256') -or -not $PSBoundParameters.ContainsKey('SourceUrl'))) {
    throw 'Updates require explicit -ExpectedSha256 and -SourceUrl for the reviewed release.'
}
if ($SourceUrl -notmatch '^https://www\.curseforge\.com/wow/addons/libprofessiondb/files/[0-9]+/?$') {
    throw 'SourceUrl must be the official LibProfessionDB release page.'
}
$archive = (Resolve-Path $ArchivePath).Path
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $ExpectedSha256) {
    throw 'Archive SHA-256 does not match the reviewed release.'
}
$AddonRoot = (Resolve-Path $AddonRoot).Path
$validator = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests\embedded_library_spec.ps1'
$ownedPaths = @('libs/LibStub', 'libs/LibProfessionDB-1.0', 'libs/LibProfessionDB.lock.json', 'embeds.xml')
$hasExisting = @( $ownedPaths | Where-Object { Test-Path (Join-Path $AddonRoot $_) } ).Count -gt 0
if ($hasExisting) {
    & $validator -AddonRoot $AddonRoot -MoonSharpPath $MoonSharpPath
}
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('HordeEternal-import-' + [guid]::NewGuid())
$zip = $null
try {
    [System.IO.Directory]::CreateDirectory($staging) | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    if ($zip.Entries.Count -gt 10000) { throw 'Archive entry limit exceeded.' }
    $entries = @{}
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        if ($entries.ContainsKey($name)) { throw "Duplicate archive entry: $name" }
        $entries[$name] = $entry
    }
    $manifestEntry = $entries['ProfessionDB/ProfessionDB_Camelot.toc']
    if (-not $manifestEntry -or $manifestEntry.Length -gt 1MB) { throw 'Forever manifest missing or oversized.' }
    $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
    try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($manifestText -notmatch '(?m)^## Interface:\s*16001\s*\r?$') { throw 'Release does not target the pinned Forever interface.' }
    $versionMatch = [regex]::Match($manifestText, '(?m)^## Version:\s*ProfessionDB-v([0-9]+\.[0-9]+\.[0-9]+)\s*\r?$')
    if (-not $versionMatch.Success) { throw 'Unrecognized release version; review the upstream manifest.' }
    $version = $versionMatch.Groups[1].Value
    $payload = @()
    $seenPayload = @{}
    foreach ($line in ($manifestText -split '\r?\n')) {
        $line = $line.Trim().Replace('/', '\')
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -in @('libs\LibStub\LibStub.lua', 'LibProfessionDB-1.0.lua', 'ProfessionDB.lua')) { continue }
        if ($line -notmatch '^Data\\Forever\\[A-Za-z_]+\\[A-Za-z0-9_]+\.lua$' -or $seenPayload.ContainsKey($line)) {
            throw "Unexpected or duplicate Forever script; review upstream changes: $line"
        }
        $seenPayload[$line] = $true
        $payload += $line
    }
    if ($payload.Count -lt 10 -or $payload.Count -gt 1000) { throw 'Unexpected Forever data manifest size.' }
    $imports = @(
        @{ source = 'libs\LibStub\LibStub.lua'; path = 'libs/LibStub/LibStub.lua' },
        @{ source = 'LibProfessionDB-1.0.lua'; path = 'libs/LibProfessionDB-1.0/LibProfessionDB-1.0.lua' },
        @{ source = 'LICENSE'; path = 'libs/LibProfessionDB-1.0/LICENSE' }
    )
    foreach ($file in $payload) {
        $imports += @{ source = $file; path = 'libs/LibProfessionDB-1.0/' + $file.Replace('\', '/') }
    }
    $payloadBytes = 0
    foreach ($entry in $imports) {
        $source = $entries['ProfessionDB/' + $entry.source.Replace('\', '/')]
        if (-not $source -or $source.Length -gt 8MB) { throw "Missing or oversized payload: $($entry.source)" }
        $payloadBytes += $source.Length
        if ($payloadBytes -gt 64MB) { throw 'Total embedded payload size limit exceeded.' }
        $destination = Join-Path $staging $entry.path
        [System.IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($source, $destination)
        $entry.sha256 = (Get-FileHash $destination -Algorithm SHA256).Hash
    }
    $engine = Get-Content (Join-Path $staging 'libs/LibProfessionDB-1.0/LibProfessionDB-1.0.lua') -Raw
    $minorMatch = [regex]::Match($engine, 'local MAJOR, MINOR = "LibProfessionDB-1\.0", ([0-9]+)')
    if (-not $minorMatch.Success) { throw 'Unrecognized library registration; review upstream API changes.' }
    $builds = @{}
    $recipeCount = 0
    foreach ($entry in $imports) {
        if ($entry.path -notlike '*/Data/Forever/_core/*') { continue }
        $header = Get-Content (Join-Path $staging $entry.path) -TotalCount 8
        $match = [regex]::Match(($header -join "`n"), '(?m)^-- build ([0-9.]+) - ([0-9]+) recipes\r?$')
        if ($match.Success) {
            $builds[$match.Groups[1].Value] = $true
            $recipeCount += [int]$match.Groups[2].Value
        }
    }
    if ($builds.Count -ne 1 -or $recipeCount -lt 1 -or $recipeCount -gt 5000) {
        throw 'Unrecognized or oversized recipe snapshot; review client coverage and catalogue limits.'
    }
    $document = New-Object System.Xml.XmlDocument
    $namespace = 'http://www.blizzard.com/wow/ui/'
    $root = $document.CreateElement('Ui', $namespace)
    $document.AppendChild($root) | Out-Null
    foreach ($entry in $imports) {
        if (-not $entry.path.EndsWith('.lua')) { continue }
        $script = $document.CreateElement('Script', $namespace)
        $script.SetAttribute('file', $entry.path.Replace('/', '\'))
        $root.AppendChild($script) | Out-Null
    }
    $document.Save((Join-Path $staging 'embeds.xml'))
    $lock = [ordered]@{
        project = 'LibProfessionDB'
        version = $version
        libStubMajor = 'LibProfessionDB-1.0'
        libStubMinor = [int]$minorMatch.Groups[1].Value
        source = $SourceUrl
        archiveSha256 = $ExpectedSha256.ToUpperInvariant()
        game = 'Forever'
        dataBuild = @($builds.Keys)[0]
        expectedRecipes = $recipeCount
        files = @($imports | ForEach-Object { [ordered]@{ path = $_.path; sha256 = $_.sha256 } })
    }
    $json = $lock | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $staging 'libs/LibProfessionDB.lock.json'), $json + "`n")
    Copy-Item -LiteralPath (Join-Path $AddonRoot 'HordeEternal.toc') -Destination $staging
    & $validator -AddonRoot $staging -MoonSharpPath $MoonSharpPath
    $scripts = @($document.SelectNodes('//*[local-name()="Script"]'))
    Write-Output "Validated LibProfessionDB $version ($recipeCount declared recipes, $($scripts.Count) scripts)."
    if ($CheckOnly) {
        Write-Output 'CHECK ONLY: no installed files were changed.'
        return
    }
    if ($hasExisting -and -not $Update) {
        $current = Get-Content (Join-Path $AddonRoot 'libs/LibProfessionDB.lock.json') -Raw | ConvertFrom-Json
        if ($current.archiveSha256 -eq $ExpectedSha256) {
            Write-Output 'PASS: this pinned archive is already installed and verified.'
            return
        }
        throw 'Replacing an existing release requires -Update. Use -CheckOnly to preview first.'
    }
    $backup = Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid())
    $backedUp, $installed = @(), @()
    try {
        foreach ($path in $ownedPaths) {
            $destination = Join-Path $AddonRoot $path
            if (Test-Path $destination) {
                $saved = Join-Path $backup $path
                [System.IO.Directory]::CreateDirectory((Split-Path $saved -Parent)) | Out-Null
                Move-Item -LiteralPath $destination -Destination $saved
                $backedUp += $path
            }
        }
        foreach ($path in $ownedPaths) {
            $destination = Join-Path $AddonRoot $path
            [System.IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
            Move-Item -LiteralPath (Join-Path $staging $path) -Destination $destination
            $installed += $path
        }
        & $validator -AddonRoot $AddonRoot -MoonSharpPath $MoonSharpPath
    } catch {
        foreach ($path in $installed) { Remove-Item -LiteralPath (Join-Path $AddonRoot $path) -Recurse -Force }
        foreach ($path in $backedUp) { Move-Item -LiteralPath (Join-Path $backup $path) -Destination (Join-Path $AddonRoot $path) }
        throw
    }
    Write-Output "PASS: installed LibProfessionDB $version. Backup: $backup"
} finally {
    if ($zip) { $zip.Dispose() }
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}