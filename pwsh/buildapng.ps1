#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]
Write-Host "Detected Qt Version $qtVersion"

# Clone
git clone https://github.com/jdpurcell/QtApng.git
cd QtApng
git checkout master

# Dependencies
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
} elseif ($IsMacOS) {
    if ($qtVersion -ge [version]"6.5.3") {
        # GitHub macOS 13/14 runners use Xcode 15.0.x by default which has a known linker issue causing crashes if the artifact is run on macOS <= 12
        sudo xcode-select --switch /Applications/Xcode_15.3.app
    } else {
        # Keep older Qt versions on Xcode 14 due to concern over QTBUG-117484
        sudo xcode-select --switch /Applications/Xcode_14.3.1.app
    }
}
if ($IsWindows) {
    choco install ninja pkgconfiglite
} elseif ($IsMacOS) {
    brew update
    brew install ninja
} else {
    sudo apt-get install ninja-build
}

# Build
$argApngQt6 = $qtVersion -lt [version]"6.0" ? "-DAPNG_QT6=OFF" : $null
$argDeviceArchs = $IsMacOS -and $qtVersion.Major -eq 5 ? "-DCMAKE_OSX_ARCHITECTURES=x86_64" : $null
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release $argDeviceArchs $argApngQt6
ninja -C build

if ($env:universalBinary -eq 'true') {
    cmake -B build_intel -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
    ninja -C build_intel
}

# Copy output
$outputDir = "output"
mkdir $outputDir
$files = Get-ChildItem -Path "build/plugins/imageformats" | Where-Object { $_.Extension -in ".dylib", ".dll", ".so" }
foreach ($file in $files) {
    if ($env:universalBinary -eq 'true') {
        $name = $file.Name
        lipo -create "$file" "build_intel/plugins/imageformats/$name" -output "$outputDir/$name"
        lipo -info "$outputDir/$name"
    } else {
        Copy-Item -Path $file -Destination $outputDir
    }
}
