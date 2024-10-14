#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]

$kde_vers = $args[0]
$kfMajorVer = $kde_vers -like 'v5.*' ? 5 : 6

# Clone
git clone https://invent.kde.org/frameworks/karchive.git
cd karchive
git checkout $kde_vers

if ($IsMacOS) {
    # Uninstall this because there's only one architecture installed, which
    # prevents the other architecture of the universal binary from building
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
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed/" -DCMAKE_BUILD_TYPE=Release $argQt6 -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" $argDeviceArchs .

ninja
ninja install

# Build intel version as well and macos and lipo them together
if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    Write-Host "Building intel binaries"

    rm -rf CMakeFiles/
    rm -rf CMakeCache.txt

    cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed_intel/" -DCMAKE_BUILD_TYPE=Release $argQt6 -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET="x64-osx" -DCMAKE_OSX_ARCHITECTURES="x86_64" .

    ninja
    ninja install
}

function FindKArchiveDir() {
    return Split-Path -Path (Get-Childitem -Include "KF$($kfMajorVer)ArchiveConfig.cmake" -Recurse -ErrorAction SilentlyContinue)[0]
}

cd installed/ -ErrorAction Stop
[Environment]::SetEnvironmentVariable("KF$($kfMajorVer)Archive_DIR", (FindKArchiveDir))
cd ../

if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    cd installed_intel/ -ErrorAction Stop
    [Environment]::SetEnvironmentVariable("KF$($kfMajorVer)Archive_DIR_INTEL", (FindKArchiveDir))
    cd ../
}

cd ../
