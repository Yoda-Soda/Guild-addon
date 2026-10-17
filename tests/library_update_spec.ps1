param(
    [string]$ArchivePath = (Join-Path $env:TEMP 'HordeEternal-ProfessionDB-1.9.1\ProfessionDB.zip')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$importer = Join-Path $repoRoot 'tools/Import-ProfessionDB.ps1'
$temporary = Join-Path $env:TEMP ('HordeEternal-update-test-' + [guid]::NewGuid())
$fixture = Join-Path $temporary 'HordeEternal'
$backupRoot = Join-Path $temporary 'backups'
[System.IO.Directory]::CreateDirectory($fixture) | Out-Null

function Fingerprint([string]$Root) {
    return (@(Get-ChildItem $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($Root.Length) + ':' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}

function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notlike "*$Expected*") { throw }
        return
    }
    throw "Expected rejection: $Expected"
}

function Read-ZipText($Zip, [string]$Name) {
    $reader = New-Object System.IO.StreamReader($Zip.GetEntry($Name).Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Write-ZipText($Zip, [string]$Name, [string]$Text) {
    $old = $Zip.GetEntry($Name)
    if ($old) { $old.Delete() }
    $entry = $Zip.CreateEntry($Name)
    $writer = New-Object System.IO.StreamWriter($entry.Open())
    try { $writer.Write($Text) } finally { $writer.Dispose() }
}

try {
    $source = Join-Path $repoRoot 'HordeEternal'
    Copy-Item (Join-Path $source 'HordeEternal.toc'), (Join-Path $source 'embeds.xml') -Destination $fixture
    Copy-Item (Join-Path $source 'libs') -Destination $fixture -Recurse
    $unrelated = Join-Path $fixture 'libs/Unrelated/keep.txt'
    [System.IO.Directory]::CreateDirectory((Split-Path $unrelated -Parent)) | Out-Null
    [System.IO.File]::WriteAllText($unrelated, 'unrelated addon data')
    $original = Fingerprint $fixture
    $nextArchive = Join-Path $temporary 'next-release-fixture.zip'
    Copy-Item -LiteralPath $ArchivePath -Destination $nextArchive
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($nextArchive, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $tocName = 'ProfessionDB/ProfessionDB_Camelot.toc'
        $toc = (Read-ZipText $zip $tocName).Replace('ProfessionDB-v1.9.1', 'ProfessionDB-v1.9.2')
        $toc = $toc.Replace('Data\Forever\enGB\RecipeScrollPrefixes.lua', 'Data\Forever\enGB\UpdateFixture.lua')
        Write-ZipText $zip $tocName $toc
        $zip.GetEntry('ProfessionDB/Data/Forever/enGB/RecipeScrollPrefixes.lua').Delete()
        Write-ZipText $zip 'ProfessionDB/Data/Forever/enGB/UpdateFixture.lua' 'return'
        $nameFile = 'ProfessionDB/Data/Forever/enUS/Alchemy.lua'
        $names = (Read-ZipText $zip $nameFile).Replace('Elixir of Minor Strength', 'Fixture updated name')
        Write-ZipText $zip $nameFile $names
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash $nextArchive -Algorithm SHA256).Hash
    $arguments = @{
        ArchivePath = $nextArchive
        ExpectedSha256 = $hash
        SourceUrl = 'https://www.curseforge.com/wow/addons/libprofessiondb/files/12345678'
        AddonRoot = $fixture
        BackupRoot = $backupRoot
    }
    & $importer @arguments -CheckOnly | Out-Null
    if ((Fingerprint $fixture) -ne $original -or (Test-Path $backupRoot)) { throw 'Preview changed installed files.' }
    Assert-Rejected { & $importer @arguments } 'requires -Update'
    Assert-Rejected { & $importer -ArchivePath $nextArchive -AddonRoot $fixture -Update } 'require explicit'
    Assert-Rejected { & $importer -ArchivePath $nextArchive -AddonRoot $fixture } 'SHA-256 does not match'
    if ((Fingerprint $fixture) -ne $original) { throw 'Rejected update changed installed files.' }

    $enginePath = Join-Path $fixture 'libs/LibProfessionDB-1.0/LibProfessionDB-1.0.lua'
    $engineBytes = [System.IO.File]::ReadAllBytes($enginePath)
    [System.IO.File]::AppendAllText($enginePath, "`n")
    Assert-Rejected { & $importer @arguments -Update } 'Dependency differs from upstream'
    [System.IO.File]::WriteAllBytes($enginePath, $engineBytes)

    $failureState = @{ armed = $true; destination = (Join-Path $fixture 'embeds.xml') }
    function Move-Item {
        [CmdletBinding()]
        param([string]$LiteralPath, [string]$Destination)
        if ($failureState.armed -and $Destination -eq $failureState.destination -and $LiteralPath -like '*HordeEternal-import-*') {
            $failureState.armed = $false
            throw 'Simulated installation write failure'
        }
        Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
    }
    try { Assert-Rejected { & $importer @arguments -Update } 'Simulated installation write failure' }
    finally { Remove-Item Function:\Move-Item }
    if ((Fingerprint $fixture) -ne $original) { throw 'Rollback did not restore the original package.' }

    & $importer @arguments -Update | Out-Null
    $updated = Get-Content (Join-Path $fixture 'libs/LibProfessionDB.lock.json') -Raw | ConvertFrom-Json
    if ($updated.version -ne '1.9.2' -or $updated.archiveSha256 -ne $hash) { throw 'Release pin was not updated.' }
    if (Test-Path (Join-Path $fixture 'libs/LibProfessionDB-1.0/Data/Forever/enGB/RecipeScrollPrefixes.lua')) {
        throw 'Obsolete vendor file survived update.'
    }
    if (-not (Test-Path (Join-Path $fixture 'libs/LibProfessionDB-1.0/Data/Forever/enGB/UpdateFixture.lua'))) {
        throw 'New vendor file was not installed.'
    }
    if ((Get-Content $unrelated -Raw) -ne 'unrelated addon data') { throw 'Unrelated file changed.' }
    if (-not (Get-ChildItem $backupRoot -Recurse -Filter 'LibProfessionDB.lock.json')) { throw 'Rollback backup missing.' }
    $afterUpdate = Fingerprint $fixture
    & $importer @arguments | Out-Null
    if ((Fingerprint $fixture) -ne $afterUpdate) { throw 'Reimport was not idempotent.' }
    Write-Output 'PASS: preview, explicit upgrade, checksum rejection, local-edit protection, backup, rollback, stale-file removal, and unrelated-file preservation.'
} finally {
    if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}