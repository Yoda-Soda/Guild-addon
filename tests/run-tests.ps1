param(
    [string]$MoonSharpPath,
    [switch]$SkipLua,
    [switch]$SkipEmbedded
)

# Runs every check a contributor can run locally, on Windows PowerShell 5.1.
#   .\tests\run-tests.ps1
#   .\tests\run-tests.ps1 -SkipLua
#
# tests/library_update_spec.ps1 is excluded on purpose: it needs the upstream
# ProfessionDB release archive, which only the maintainer keeps.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$defaultMoonSharp = Join-Path $env:TEMP 'HordeEternal-LuaTests\lib\net40-client\MoonSharp.Interpreter.dll'

$resolvedMoonSharp = $MoonSharpPath
if (-not $resolvedMoonSharp) { $resolvedMoonSharp = $defaultMoonSharp }

if (-not $SkipLua) {
    if (-not (Test-Path $resolvedMoonSharp)) {
        $resolvedMoonSharp = (& (Join-Path $PSScriptRoot 'Get-MoonSharp.ps1')).Trim()
    }
    if (-not (Test-Path $resolvedMoonSharp)) {
        throw "MoonSharp was not provisioned; expected '$resolvedMoonSharp'."
    }
}

Push-Location $repoRoot
try {
    if (-not $SkipEmbedded) {
        & (Join-Path $PSScriptRoot 'embedded_library_spec.ps1') -MoonSharpPath $resolvedMoonSharp
    }

    if ($SkipLua) {
        Write-Warning 'Lua specs skipped (-SkipLua).'
        return
    }

    # LoadFrom is safe even though embedded_library_spec.ps1 already loaded the
    # same assembly through Add-Type: it returns the loaded instance.
    $assembly = [System.Reflection.Assembly]::LoadFrom($resolvedMoonSharp)

    # Specs resolve addon files with loadfile("HordeEternal/..."), so the working
    # directory must be the repository root.
    foreach ($name in @('crafting_spec.lua', 'guild_spec.lua', 'members_spec.lua', 'map_spec.lua', 'scanning_spec.lua')) {
        $file = Join-Path $PSScriptRoot $name
        if (-not (Test-Path $file)) { throw "Missing test file: $file" }

        $script = $assembly.CreateInstance('MoonSharp.Interpreter.Script')
        $script.Options.DebugPrint = [System.Action[string]] { param($message) Write-Host $message }

        try {
            $script.DoFile($file, $null, $null) | Out-Null
        }
        catch {
            $exception = $_.Exception
            $inner = $exception.InnerException
            if ($inner) {
                $detail = $inner.DecoratedMessage
                if (-not $detail) { $detail = $inner.Message }
            }
            else {
                $detail = $exception.Message
            }
            throw "Lua spec failed: $name`n$detail"
        }

        Write-Output "PASS: $name"
    }
}
finally {
    Pop-Location
}
