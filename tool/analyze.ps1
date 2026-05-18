$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

$workspaceRoot = Split-Path -Parent $PSScriptRoot

Push-Location $workspaceRoot
try {
    & flutter analyze apps/common_code_desktop
    & dart analyze packages/common_code_domain
    & dart analyze packages/host_core
}
finally {
    Pop-Location
}
