#!/usr/bin/env pwsh

$qtVersion = [version](qmake -query QT_VERSION)

$kfGitRef = $args[0]
$kfMajorVer = $kfGitRef -like 'v5.*' ? 5 : 6

# Clone
git clone https://invent.kde.org/frameworks/karchive.git
cd karchive
git checkout $kfGitRef

if ($IsMacOS) {
    # We don't need the zstd feature and it will crash at runtime if this one is used anyway
    brew uninstall --ignore-dependencies zstd
}

$argQt6 = $qtVersion.Major -eq 6 ? '-DBUILD_WITH_QT6=ON' : $null
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -in 'Arm64', 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $null
}

# Build
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed" -DCMAKE_BUILD_TYPE=Release $argQt6 -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DWITH_OPENSSL=OFF -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_INSTALLED_DIR="$env:VCPKG_ROOT/installed-$env:VCPKG_DEFAULT_TRIPLET" $argDeviceArchs .

ninja
ninja install

# Build intel version as well and macos and lipo them together
if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    Write-Host "Building intel binaries"

    rm -rf CMakeFiles/
    rm -rf CMakeCache.txt

    cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed_intel" -DCMAKE_BUILD_TYPE=Release $argQt6 -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DWITH_OPENSSL=OFF -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_INSTALLED_DIR="$env:VCPKG_ROOT/installed-x64-osx" -DVCPKG_TARGET_TRIPLET="x64-osx" -DCMAKE_OSX_ARCHITECTURES="x86_64" .

    ninja
    ninja install
}

function FindKArchiveDir() {
    return Split-Path -Path (Get-Childitem -Include "KF${kfMajorVer}ArchiveConfig.cmake" -Recurse -ErrorAction SilentlyContinue)[0]
}

cd installed/ -ErrorAction Stop
[Environment]::SetEnvironmentVariable("KF${kfMajorVer}Archive_DIR", (FindKArchiveDir))
cd ../

if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    cd installed_intel/ -ErrorAction Stop
    [Environment]::SetEnvironmentVariable("KF${kfMajorVer}Archive_DIR_INTEL", (FindKArchiveDir))
    cd ../
}

cd ../
