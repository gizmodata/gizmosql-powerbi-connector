<#
.SYNOPSIS
    Packages the Power BI connectors in powerbi/ into .mez files (a .mez is a
    zip of the .pq section document + resources.resx + the .pqm modules).

.PARAMETER Install
    Also copy the produced .mez files into the user's Power BI Desktop
    Custom Connectors folder.

.EXAMPLE
    pwsh scripts/build-mez.ps1
    pwsh scripts/build-mez.ps1 -Install
#>

[CmdletBinding()]
param(
    [switch] $Install
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$pb = Join-Path $repoRoot 'powerbi'

$shared = @('resources.resx', 'SqlGenerator.pqm', 'SqlGeneratorCommon.pqm')
$connectors = @(
    @{ Section = 'GizmoSql.m'; Mez = 'GizmoSql.mez' }
)

foreach ($c in $connectors) {
    $stage = Join-Path $env:TEMP ('mez_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $pqName = [IO.Path]::GetFileNameWithoutExtension($c.Section) + '.pq'
    Copy-Item -LiteralPath (Join-Path $pb $c.Section) -Destination (Join-Path $stage $pqName)
    foreach ($s in $shared) { Copy-Item -LiteralPath (Join-Path $pb $s) -Destination $stage }
    # Connector icons (referenced by Extension.Contents in the Publish record).
    foreach ($icon in Get-ChildItem -LiteralPath (Join-Path $pb 'icons') -Filter 'GizmoSql*.png') {
        Copy-Item -LiteralPath $icon.FullName -Destination $stage
    }
    $mez = Join-Path $pb $c.Mez
    $files = Get-ChildItem -LiteralPath $stage -File
    Compress-Archive -LiteralPath $files.FullName -DestinationPath $mez -Force
    Write-Host ("Built {0} ({1:N1} KB)" -f $c.Mez, ((Get-Item -LiteralPath $mez).Length / 1KB))
}

if ($Install) {
    $cc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Power BI Desktop\Custom Connectors'
    if (-not (Test-Path -LiteralPath $cc)) { New-Item -ItemType Directory -Path $cc | Out-Null }
    foreach ($c in $connectors) {
        Copy-Item -LiteralPath (Join-Path $pb $c.Mez) -Destination $cc -Force
    }
    Write-Host "Installed to: $cc"
}
