param(
  [string]$AvdName = "Pixel_6a",
  [string]$ApiBaseUrl = "http://10.0.2.2:8000",
  [string]$GoogleWebClientId = "<WEB_CLIENT_ID>"
)

$ErrorActionPreference = "Stop"

$sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$emulatorExe = Join-Path $sdkRoot "emulator\emulator.exe"
$adbExe = Join-Path $sdkRoot "platform-tools\adb.exe"
$flutterExe = "C:\Users\nihal\flutter_sdk\bin\flutter.bat"
$mobileDir = Join-Path $PSScriptRoot "..\mobile"

if (!(Test-Path $emulatorExe)) {
  throw "Android emulator not found at $emulatorExe"
}

if (!(Test-Path $adbExe)) {
  throw "adb not found at $adbExe"
}

if (!(Test-Path $flutterExe)) {
  throw "Flutter SDK not found at $flutterExe"
}

$existing = & $adbExe devices | Select-String "emulator-.*device"
if (-not $existing) {
  Start-Process -FilePath $emulatorExe -ArgumentList "-avd $AvdName"
}

Write-Host "Waiting for emulator to boot..."
& $adbExe wait-for-device | Out-Null

$bootComplete = $false
for ($i = 0; $i -lt 90; $i++) {
  $status = (& $adbExe shell getprop sys.boot_completed 2>$null).Trim()
  if ($status -eq "1") {
    $bootComplete = $true
    break
  }
  Start-Sleep -Seconds 2
}

if (-not $bootComplete) {
  throw "Emulator boot timed out."
}

& $adbExe reverse tcp:8000 tcp:8000

$emulatorId = (
  & $adbExe devices |
  Where-Object { $_ -match "^emulator-\d+\s+device$" } |
  ForEach-Object { ($_ -split "\s+")[0] } |
  Select-Object -First 1
)

if (-not $emulatorId) {
  throw "No running emulator device found after boot."
}

Set-Location $mobileDir
& $flutterExe pub get
& $flutterExe run -d $emulatorId --dart-define=API_BASE_URL=$ApiBaseUrl --dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId
