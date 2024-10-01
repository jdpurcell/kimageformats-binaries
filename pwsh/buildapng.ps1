#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]
Write-Host "Detected Qt Version $qtVersion"

# Clone
git clone https://github.com/jdpurcell/QtApng.git
cd QtApng
git checkout master

# Dependencies
if ($IsWindows) {
    if ($env:buildArch -eq 'Arm64') {
        $env:QT_HOST_PATH = [System.IO.Path]::GetFullPath("$env:QT_ROOT_DIR\..\$((Split-Path -Path $env:QT_ROOT_DIR -Leaf) -replace '_arm64', '_64')")
    }
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"

    # Workaround for https://developercommunity.visualstudio.com/t/10664660
    $env:CXXFLAGS += " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR"
    $env:CFLAGS += " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR"
} elseif ($IsMacOS) {
    if ($qtVersion -lt [version]"6.5.3") {
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
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -in 'Arm64', 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $null
}
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release $argDeviceArchs $argApngQt6
ninja -C build

if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    cmake -B build_intel -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
    ninja -C build_intel
}

# Copy output
$outputDir = "output"
mkdir $outputDir
$files = Get-ChildItem -Path "build/plugins/imageformats" | Where-Object { $_.Extension -in ".dylib", ".dll", ".so" }
foreach ($file in $files) {
    if ($IsMacOS -and $env:buildArch -eq 'Universal') {
        $name = $file.Name
        lipo -create "$file" "build_intel/plugins/imageformats/$name" -output "$outputDir/$name"
        lipo -info "$outputDir/$name"
    } else {
        Copy-Item -Path $file -Destination $outputDir
    }
}
