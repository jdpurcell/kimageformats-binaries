#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]

# Clone
git clone https://invent.kde.org/frameworks/karchive.git
cd karchive
git checkout $args[0]

if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE\pwsh\vcvars.ps1"
} elseif ($IsMacOS) {
    # don't use homebrew zlib/zstd
    brew uninstall --ignore-dependencies zlib
    brew uninstall --ignore-dependencies zstd
}

if ($qtVersion.Major -eq 6) {
    $qt6flag = "-DBUILD_WITH_QT6=ON"
}
if ($IsWindows -and [Environment]::Is64BitOperatingSystem -and $env:forceWin32 -eq 'true') {
    $argTargetTriplet = "-DVCPKG_TARGET_TRIPLET=x86-windows"
} elseif ($IsMacOS -and $qtVersion.Major -eq 5) {
    $argTargetTriplet = "-DVCPKG_TARGET_TRIPLET=x64-osx"
    $argDeviceArchs = "-DCMAKE_OSX_ARCHITECTURES=x86_64"
}

# Build
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed/" -DCMAKE_BUILD_TYPE=Release $qt6flag -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" $argTargetTriplet $argDeviceArchs .

ninja
ninja install

# Build intel version as well and macos and lipo them together
if ($env:universalBinary -eq 'true') {
    Write-Host "Building intel binaries"

    rm -rf CMakeFiles/
    rm -rf CMakeCache.txt

    cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed_intel/" -DCMAKE_BUILD_TYPE=Release $qt6flag -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET="x64-osx" -DCMAKE_OSX_ARCHITECTURES="x86_64" .

    ninja
    ninja install
}

try {
    cd installed/ -ErrorAction Stop

    $env:KF5Archive_DIR = Split-Path -Path (Get-Childitem -Include KF5ArchiveConfig.cmake -Recurse -ErrorAction SilentlyContinue)[0]

    cd ../

    if ($env:universalBinary -eq 'true') {
        cd installed_intel/ -ErrorAction Stop

        $env:KF5Archive_DIR_INTEL = Split-Path -Path (Get-Childitem -Include KF5ArchiveConfig.cmake -Recurse -ErrorAction SilentlyContinue)[0]

        cd ../
    }
} catch {}

cd ../
