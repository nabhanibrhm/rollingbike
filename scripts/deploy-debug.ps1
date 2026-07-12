# Builds a DEBUG APK and installs+runs it on the connected phone.
# Debug is what goes on the device for day-to-day testing.
#   Usage:  ./scripts/deploy-debug.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

Write-Host "==> Building & installing DEBUG on device..." -ForegroundColor Cyan
flutter run --debug
