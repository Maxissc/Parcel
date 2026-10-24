#requires -Version 5.1
# Corre los tests de los dos paquetes del workspace. Se ejecuta desde cualquier carpeta.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Push-Location (Join-Path $root 'packages/core')
try {
    dart test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}

Push-Location (Join-Path $root 'app_desktop')
try {
    flutter test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
