$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

$workspaceRoot = Split-Path -Parent $PSScriptRoot

Push-Location $workspaceRoot
try {
    & dart pub get
}
finally {
    Pop-Location
}
