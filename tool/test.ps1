$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

$workspaceRoot = Split-Path -Parent $PSScriptRoot

Push-Location $workspaceRoot
try {
    & flutter test apps/common_code_desktop
    & dart test packages/common_code_domain
    & dart test packages/host_core
}
finally {
    Pop-Location
}
