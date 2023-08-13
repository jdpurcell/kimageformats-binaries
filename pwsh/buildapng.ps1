#!/usr/bin/env pwsh

# Clone
git clone https://github.com/jdpurcell/QtApng.git
cd QtApng
git checkout 4a74aac43eb0ba4787f9e8ef8cf0fb1ef6b14792



# Build

# vcvars on windows
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
}

qmake "CONFIG += libpng_static" QMAKE_APPLE_DEVICE_ARCHS="x86_64 arm64"
if ($IsWindows) {
    nmake
} else {
    make
}
cd ..
