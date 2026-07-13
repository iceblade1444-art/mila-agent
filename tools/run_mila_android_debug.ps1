$ErrorActionPreference = 'Stop'

$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$definesPath = Join-Path $env:TEMP 'mila_flutter_defines.json'

if (-not $env:GEMINI_API_KEY) {
  throw 'GEMINI_API_KEY is not set in the Windows environment.'
}

@{
  GEMINI_API_KEY = $env:GEMINI_API_KEY
  MILA_BACKEND_URL = 'https://agent.milanapremium.uz'
  APP_VERSION = '1.0.1'
  APP_VERSION_CODE = '2'
} | ConvertTo-Json | Set-Content -Encoding UTF8 -Path $definesPath

$running = & $adb devices | Select-String 'emulator-5554\s+device'
if (-not $running) {
  Start-Process -FilePath $emulator -ArgumentList '-allow-host-audio -avd MILA_API_34 -netdelay none -netspeed full'
  do {
    Start-Sleep -Seconds 3
    $booted = & $adb shell getprop sys.boot_completed 2>$null
  } until ($booted -match '1')
}

& "$PSScriptRoot\..\..\..\FlutterSDK\bin\flutter.bat" run `
  -d emulator-5554 `
  --dart-define-from-file="$definesPath"
