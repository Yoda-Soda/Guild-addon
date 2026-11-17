param(
    [string]$Version = '2.0.0',
    [string]$Root = (Join-Path $env:TEMP 'HordeEternal-LuaTests')
)

# Provisions the MoonSharp Lua interpreter used by the test suite.
# Layout matches the default -MoonSharpPath of the existing scripts:
#   %TEMP%\HordeEternal-LuaTests\lib\net40-client\MoonSharp.Interpreter.dll
# Prints the resolved DLL path so callers can capture it.

$ErrorActionPreference = 'Stop'

$dllPath = Join-Path $Root 'lib/net40-client/MoonSharp.Interpreter.dll'
if (Test-Path $dllPath) {
    Write-Output $dllPath
    return
}

# NuGet package id is 'moonsharp' (not 'moonsharp.interpreter'); the assembly
# inside it is MoonSharp.Interpreter.dll.
$url = "https://api.nuget.org/v3-flatcontainer/moonsharp/$Version/moonsharp.$Version.nupkg"
$nupkg = Join-Path $env:TEMP "moonsharp.$Version.nupkg"

New-Item -ItemType Directory -Force -Path $Root | Out-Null

if (-not (Test-Path $nupkg)) {
    Write-Host "Downloading MoonSharp $Version from NuGet..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$stage = Join-Path $env:TEMP ('moonsharp-stage-' + [guid]::NewGuid().ToString('N'))
try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $stage)
    Copy-Item -Path (Join-Path $stage '*') -Destination $Root -Recurse -Force
}
finally {
    if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

if (-not (Test-Path $dllPath)) {
    $found = Get-ChildItem -Path $Root -Recurse -Filter 'MoonSharp.Interpreter.dll' | Select-Object -First 1
    if (-not $found) { throw "MoonSharp.Interpreter.dll was not found in $nupkg" }
    $dllPath = $found.FullName
}

Write-Output $dllPath
