param(
    [string]$TocPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'HordeEternal/HordeEternal.toc'),
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

# Guards the one property that silently broke before: the TOC version is the
# single source of truth for the release, so it must be valid and must agree
# with the tag being released.
#
#   - always: ## Version is a plain MAJOR.MINOR.PATCH
#   - on a tag build (refs/tags/v*): the tag must equal the TOC version
#   - otherwise: the TOC version must not be behind the newest release tag,
#     so a stale version cannot be packaged under an old name.
#
# Requires tags to be present, i.e. actions/checkout with fetch-depth: 0.

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $TocPath)) { throw "TOC not found: $TocPath" }

$versionLine = Get-Content $TocPath | Where-Object { $_ -match '^##\s*Version:\s*(\S+)' } | Select-Object -First 1
if (-not $versionLine) { throw 'No ## Version line found in the TOC.' }
$version = [regex]::Match($versionLine, '^##\s*Version:\s*(\S+)').Groups[1].Value

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "TOC version '$version' is not a plain MAJOR.MINOR.PATCH version."
}

Push-Location $RepoRoot
try {
    $ref = $env:GITHUB_REF
    if ($ref -and $ref -like 'refs/tags/*') {
        $tag = $ref.Substring('refs/tags/'.Length)
        if ($tag -ne "v$version") {
            throw "Tag '$tag' does not match the TOC version '$version'. Expected tag 'v$version'."
        }
        Write-Output "PASS: tag '$tag' matches the TOC version $version."
        return
    }

    $latest = @(git tag --list 'v*' --sort=-v:refname 2>$null) | Select-Object -First 1
    if (-not $latest) {
        Write-Output "PASS: no release tags yet; TOC version $version accepted."
        return
    }

    $latestVersion = $latest.TrimStart('v')
    if ($latestVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "Latest tag '$latest' is not a plain MAJOR.MINOR.PATCH tag."
    }

    if ([version]$version -lt [version]$latestVersion) {
        throw "TOC version $version is older than the latest release tag $latest. Bump ## Version before packaging."
    }

    Write-Output "PASS: TOC version $version is not behind the latest release tag $latest."
}
finally {
    Pop-Location
}
