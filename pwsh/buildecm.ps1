#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]

# Clone
git clone https://invent.kde.org/frameworks/extra-cmake-modules.git
cd extra-cmake-modules
git checkout $args[0]

# vcvars on windows
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
}

# Build
$argDeviceArchs = `
    $universalBinary ? "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64" : `
    $IsMacOS -and $qtVersion.Major -eq 5 ? "-DCMAKE_OSX_ARCHITECTURES=x86_64" : `
    $null
cmake -G Ninja . $argDeviceArchs

if ($IsWindows) {
    ninja install
    $env:ECM_DIR = "$PWD\installed\Program Files (x86)\ECM\share\ECM"
} else {
    sudo ninja install
}

cd ../
