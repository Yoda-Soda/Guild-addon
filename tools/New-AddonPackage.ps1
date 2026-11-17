param(
    [string]$AddonRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'HordeEternal'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)

# Builds the CurseForge upload artifact. MAINTAINER ONLY - uploading is a manual
# step performed by the repository owner.
#
# Produces dist/HordeEternal-<version>.zip with the addon folder at the archive
# root (HordeEternal/HordeEternal.toc), which is what CurseForge expects.
# The version is read from the TOC so the artifact can never drift from it.

$ErrorActionPreference = 'Stop'

$tocPath = Join-Path $AddonRoot 'HordeEternal.toc'
if (-not (Test-Path $tocPath)) { throw "TOC not found: $tocPath" }

$versionLine = Get-Content $tocPath | Where-Object { $_ -match '^##\s*Version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine) { throw 'No ## Version line found in the TOC.' }
$version = [regex]::Match($versionLine, '^##\s*Version:\s*(\S+)').Groups[1].Value

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$archive = Join-Path $OutputDirectory "HordeEternal-$version.zip"
if (Test-Path $archive) { Remove-Item -LiteralPath $archive -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
# includeBaseDirectory = $true -> the zip contains an HordeEternal/ folder.
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path $AddonRoot).Path,
    $archive,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $true)

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$size = (Get-Item -LiteralPath $archive).Length

Write-Output "Package:  $archive"
Write-Output "Version:  $version"
Write-Output "Size:     $size bytes"
Write-Output "SHA256:   $hash"
Write-Output ''
Write-Output 'Next: upload this zip to the CurseForge project page by hand, then tag the release.'
