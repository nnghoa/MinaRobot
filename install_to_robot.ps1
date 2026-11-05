param(
    [string]$ApkPath = "E:\MTC\APK\MinaRobot\build\app\outputs\flutter-apk\app-release.apk"
)

$adb = "C:\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

Write-Host "=== Kiem tra ket noi ADB voi Board Android Allwinner A33 ===" -ForegroundColor Cyan
& $adb devices

if (-not (Test-Path $ApkPath)) {
    Write-Host "Chua tim thay file APK tai: $ApkPath" -ForegroundColor Yellow
    Write-Host "Hay chay build_apk.ps1 hoac GitHub Actions de xuat APK truoc!" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Cai dat Mina AI len Robot ===" -ForegroundColor Green
& $adb install -r -g $ApkPath

Write-Host "=== Cap quyen UART /dev/ttyS* tren Board A33 (neu co root) ===" -ForegroundColor Cyan
& $adb shell "su -c 'chmod 666 /dev/ttyS*'" 2>$null

Write-Host "=== Khoi dong Mina AI ===" -ForegroundColor Green
& $adb shell am start -n com.mtc.mina_robot/.MainActivity
