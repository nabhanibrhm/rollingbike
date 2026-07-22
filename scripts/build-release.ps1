# Builds a RELEASE APK and copies it to the release folder on D:.
# Release artifacts are archived off-project; they are NOT installed on the phone.
#   Usage:  ./scripts/build-release.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# Where release APKs are archived. Change this if you want a different spot.
$OutDir = "D:\throttlepath-release"

Write-Host "==> Building RELEASE APK..." -ForegroundColor Cyan
flutter build apk --release

$src = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $src)) { throw "Build finished but $src is missing." }

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

# Version-stamp the filename from pubspec (e.g. throttlepath-1.0.0.apk).
$ver = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim().Split('+')[0]
$dest = Join-Path $OutDir "throttlepath-$ver.apk"

Copy-Item $src $dest -Force
Write-Host "==> Release APK copied to: $dest" -ForegroundColor Green
