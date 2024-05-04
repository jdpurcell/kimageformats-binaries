#!/usr/bin/env pwsh

$qtVersion = ((qmake --version -split '\n')[1] -split ' ')[3]
Write-Host "Detected Qt Version $qtVersion"

$useQmake = $qtVersion -like '5.*' -or $qtVersion -like '6.[0-4].*'
$universalBinary = $IsMacOS -and $qtVersion -notlike '5.*'

# Clone
git clone https://github.com/jdpurcell/QtApng.git
cd QtApng
if ($useQmake) {
    git checkout qmake
} else {
    git checkout cmake
}

# Dependencies
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
}
if (-not $useQmake) {
    if ($IsWindows) {
        choco install ninja pkgconfiglite
    } elseif ($IsMacOS) {
        brew update
        brew install ninja
    } else {
        sudo apt-get install ninja-build
    }
}

# Build
if ($useQmake) {
    mkdir build
    cd build

    $argDeviceArchs = $universalBinary ? "QMAKE_APPLE_DEVICE_ARCHS=x86_64 arm64" : $null;
    qmake .. CONFIG+=libpng_static $argDeviceArchs

    if ($IsWindows) {
        nmake
    } else {
        make
    }

    cd ..
} else {
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
    ninja -C build

    if ($universalBinary) {
        cmake -B build_arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
        ninja -C build_arm64
    }
}

# Copy output
$outputDir = "output"
mkdir $outputDir
$files = Get-ChildItem -Path "build/plugins/imageformats" | Where-Object { $_.Extension -in ".dylib", ".dll", ".so" }
foreach ($file in $files) {
    if ($universalBinary -and -not $useQmake) {
        $name = $file.Name
        lipo -create "$file" "build_arm64/plugins/imageformats/$name" -output "$outputDir/$name"
        lipo -info "$outputDir/$name"
    } else {
        Copy-Item -Path $file -Destination $outputDir
    }
}
