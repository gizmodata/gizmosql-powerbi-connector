<#
.SYNOPSIS
    Publishes GizmoData.Adbc.Driver.GizmoSql.Native with Native AOT for the
    requested runtime and prints the path to the resulting shared library.

.DESCRIPTION
    Runs `dotnet publish` with PublishAot=true. On Windows, prepends
    vswhere.exe's install directory to PATH so the .NET SDK's findvcvarsall.bat
    can locate MSVC's link.exe (otherwise the AOT link fails with
    "'vswhere.exe' is not recognized").

.PARAMETER Runtime
    Target RID. Defaults to the host's. Examples: win-x64, win-arm64, linux-x64.

.PARAMETER Configuration
    Build configuration. Defaults to Release.

.EXAMPLE
    pwsh scripts/publish-native.ps1
    pwsh scripts/publish-native.ps1 -Runtime win-arm64
#>

[CmdletBinding()]
param(
    [string] $Runtime,
    [string] $Configuration = "Release"
)

$ErrorActionPreference = 'Stop'

$ri = [System.Runtime.InteropServices.RuntimeInformation]
$osp = [System.Runtime.InteropServices.OSPlatform]
$onWindows = $ri::IsOSPlatform($osp::Windows)
$onMacOS   = $ri::IsOSPlatform($osp::OSX)

if ([string]::IsNullOrEmpty($Runtime)) {
    $arch = $ri::OSArchitecture.ToString().ToLowerInvariant()
    if ($onWindows) { $Runtime = "win-$arch" }
    elseif ($onMacOS) { $Runtime = "osx-$arch" }
    else { $Runtime = "linux-$arch" }
}

if ($onWindows) {
    $vswhereDir = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
    if (Test-Path (Join-Path $vswhereDir 'vswhere.exe')) {
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $vswhereDir })) {
            $env:PATH = "$vswhereDir;$env:PATH"
        }
    } else {
        Write-Warning "vswhere.exe not found at $vswhereDir. AOT link may fail without MSVC tools."
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$project  = Join-Path $repoRoot 'src/GizmoData.Adbc.Driver.GizmoSql.Native/GizmoData.Adbc.Driver.GizmoSql.Native.csproj'

dotnet publish $project -c $Configuration -r $Runtime
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

$publishDir = Join-Path $repoRoot "src/GizmoData.Adbc.Driver.GizmoSql.Native/bin/$Configuration/net8.0/$Runtime/publish"
$lib = Get-ChildItem $publishDir -Filter 'gizmosql_adbc.*' | Where-Object { $_.Extension -in '.dll', '.so', '.dylib' } | Select-Object -First 1
Write-Host ""
Write-Host "Native ADBC driver: $($lib.FullName)"
