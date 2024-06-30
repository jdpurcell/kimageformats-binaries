#!/usr/bin/env pwsh

# Clone
git clone https://invent.kde.org/frameworks/extra-cmake-modules.git
cd extra-cmake-modules
git checkout $args[0]

# Build
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -eq 'Arm64' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $env:buildArch -eq 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64' :
        $null
}
cmake -G Ninja . $argDeviceArchs

if ($IsWindows) {
    ninja install
    $env:ECM_DIR = "$PWD\installed\Program Files (x86)\ECM\share\ECM"
} else {
    sudo ninja install
}

cd ../
