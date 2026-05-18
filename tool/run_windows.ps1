$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$projectDir = Join-Path $workspaceRoot 'apps/common_code_desktop'
$builtExe = Join-Path $projectDir 'build\windows\x64\runner\Debug\common_code_desktop.exe'
$verificationDelaySeconds = 10

Push-Location $projectDir
try {
    & flutter build windows --debug

    if (-not (Test-Path -LiteralPath $builtExe)) {
        throw "Expected Windows executable was not created at $builtExe"
    }

    $process = Start-Process -FilePath $builtExe -PassThru

    try {
        Start-Sleep -Seconds $verificationDelaySeconds

        if ($process.HasExited) {
            throw "Windows app exited early with code $($process.ExitCode)."
        }
    }
    finally {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id
        }
    }
}
finally {
    Pop-Location
}
