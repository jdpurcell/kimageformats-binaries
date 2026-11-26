#!/usr/bin/env pwsh

$qtVersion = [version](qmake -query QT_VERSION)

$kfGitRef = $args[0]

# Clone
git clone https://invent.kde.org/frameworks/extra-cmake-modules.git
cd extra-cmake-modules
git checkout $kfGitRef

# Build
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -eq 'Arm64' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $env:buildArch -eq 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64' :
        $null
}
if ($env:QT_HOST_PATH) {
    $argHostPathCheck = '-DQT_REQUIRE_HOST_PATH_CHECK=ON'
}
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed" -DCMAKE_BUILD_TYPE=Release $argDeviceArchs $argHostPathCheck .

if ($IsWindows) {
    ninja install
} else {
    sudo ninja install
}
$env:ECM_DIR = "$PWD/installed/share/ECM"

cd ../
