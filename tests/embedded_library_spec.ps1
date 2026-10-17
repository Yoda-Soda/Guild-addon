param(
    [string]$MoonSharpPath = (Join-Path $env:TEMP 'HordeEternal-LuaTests\lib\net40-client\MoonSharp.Interpreter.dll'),
    [string]$AddonRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'HordeEternal')
)

$ErrorActionPreference = 'Stop'
$lock = Get-Content (Join-Path $addonRoot 'libs/LibProfessionDB.lock.json') -Raw | ConvertFrom-Json
if ($lock.version -notmatch '^\d+\.\d+\.\d+$' -or $lock.game -ne 'Forever' -or
    $lock.libStubMajor -ne 'LibProfessionDB-1.0' -or $lock.archiveSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
    $lock.files.Count -lt 13 -or $lock.files.Count -gt 1003) {
    throw 'Unexpected pinned dependency metadata.'
}
$manifest = New-Object System.Xml.XmlDocument
$manifest.Load((Join-Path $addonRoot 'embeds.xml'))
$scripts = @($manifest.SelectNodes('//*[local-name()="Script"]'))
$expected = @($lock.files | Where-Object { $_.path.EndsWith('.lua') })
if ($scripts.Count -ne $expected.Count) { throw 'Incomplete embedded load manifest.' }
for ($index = 0; $index -lt $scripts.Count; $index++) {
    if ($scripts[$index].GetAttribute('file').Replace('\', '/') -ne $expected[$index].path) {
        throw "Embedded script order differs from pinned import at index $index."
    }
}
if ($expected[0].path -ne 'libs/LibStub/LibStub.lua' -or
    $expected[1].path -ne 'libs/LibProfessionDB-1.0/LibProfessionDB-1.0.lua') {
    throw 'LibStub and the library engine must precede all data.'
}
$seen = @{}
foreach ($entry in $lock.files) {
    $path = Join-Path $addonRoot $entry.path
    if ($entry.path -notmatch '^libs/(LibStub/LibStub\.lua|LibProfessionDB-1\.0/(LICENSE|LibProfessionDB-1\.0\.lua|Data/Forever/[A-Za-z_]+/[A-Za-z0-9_]+\.lua))$' -or
        $seen.ContainsKey($entry.path)) { throw 'Invalid or duplicate dependency path.' }
    $seen[$entry.path] = $true
    if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Dependency differs from upstream: $path" }
}
$actual = @(Get-ChildItem (Join-Path $addonRoot 'libs/LibStub'), (Join-Path $addonRoot 'libs/LibProfessionDB-1.0') -Recurse -File)
if ($actual.Count -ne $lock.files.Count) { throw 'Unexpected extra or missing dependency files.' }
$toc = @(Get-Content (Join-Path $addonRoot 'HordeEternal.toc') |
    Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') })
if ($toc[0] -ne 'embeds.xml') { throw 'Embedded libraries must load before addon consumers.' }
$metadata = Get-Content (Join-Path $addonRoot 'HordeEternal.toc') -Raw
if ($metadata -match '(?m)^## (OptionalDeps|Dependencies):.*(ProfessionDB|Ace3|VersionCheck)') {
    throw 'Standalone dependencies must not be required by the embedded package.'
}
$license = Get-Content (Join-Path $addonRoot 'libs/LibProfessionDB-1.0/LICENSE') -Raw
if ($license -notmatch 'MIT License' -or $license -notmatch 'Copyright \(c\) [0-9 -]+ Pimptasty') {
    throw 'Upstream license notice must be retained.'
}
Write-Output 'PASS: complete embedded load order, pinned file integrity, licensing, and no standalone dependency.'

if (Test-Path $MoonSharpPath) {
    Add-Type -Path $MoonSharpPath
    $compiler = New-Object MoonSharp.Interpreter.Script
    foreach ($entry in $expected) {
        try { $compiler.LoadFile((Join-Path $addonRoot $entry.path), $null, $null) | Out-Null }
        catch { throw "Lua syntax failure in $($entry.path): $($_.Exception.InnerException.DecoratedMessage)" }
    }
    Write-Output "PASS: compiled $($expected.Count) embedded Lua files without executing third-party source."
} else {
    Write-Warning 'MoonSharp not found; syntax compilation was not run. Supply -MoonSharpPath to enable it.'
}