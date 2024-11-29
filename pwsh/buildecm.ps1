#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]

$kde_vers = $args[0]

# Clone
git clone https://invent.kde.org/frameworks/extra-cmake-modules.git
cd extra-cmake-modules
git checkout $kde_vers

# Build
$argQt6 = $qtVersion.Major -eq 6 ? '-DBUILD_WITH_QT6=ON' : $null
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -eq 'Arm64' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $env:buildArch -eq 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64' :
        $null
}
cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/installed" -DCMAKE_BUILD_TYPE=Release $argQt6 $argDeviceArchs .

if ($IsWindows) {
    ninja install
} else {
    sudo ninja install
}
$env:ECM_DIR = "$PWD/installed/share/ECM"

cd ../
