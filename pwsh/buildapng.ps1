#!/usr/bin/env pwsh

$qtVersion = ((qmake --version -split '\n')[1] -split ' ')[3]
Write-Host "Detected Qt Version $qtVersion"

# Clone
git clone https://github.com/jdpurcell/QtApng.git
cd QtApng
git checkout 4a74aac43eb0ba4787f9e8ef8cf0fb1ef6b14792

# Build

# vcvars on windows
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
}

$qmakeArgs = @(
    "CONFIG+=libpng_static"
)
if ($IsMacOS -and $qtVersion -notlike '5.*') {
    $qmakeArgs += "QMAKE_APPLE_DEVICE_ARCHS=""x86_64 arm64"""
}
Write-Host "Running 'qmake', args: $qmakeArgs"
Invoke-Expression "qmake $qmakeArgs"

if ($IsWindows) {
    Write-Host "Running 'nmake'"
    nmake
} else {
    Write-Host "Running 'make'"
    make
}
