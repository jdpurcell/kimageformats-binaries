#!/usr/bin/env pwsh

# Install vcpkg if we don't already have it
if ($env:VCPKG_ROOT -eq $null) {
    git clone https://github.com/microsoft/vcpkg
    $env:VCPKG_ROOT = "$PWD/vcpkg/"
}

# Bootstrap VCPKG again
if ($IsWindows) {
    & "$env:VCPKG_ROOT/bootstrap-vcpkg.bat"
} else {
    & "$env:VCPKG_ROOT/bootstrap-vcpkg.sh"
}

# Install NASM
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"
    choco install nasm
} elseif ($IsMacOS) {
    brew install nasm
} else {
    # (and bonus dependencies)
    sudo apt-get install nasm libxi-dev libgl1-mesa-dev libglu1-mesa-dev mesa-common-dev libxrandr-dev libxxf86vm-dev
}

if ($IsWindows -and $env:buildArch -eq 'X86') {
    $env:VCPKG_DEFAULT_TRIPLET = "x86-windows"
} elseif ($IsWindows -and $env:buildArch -eq 'Arm64') {
    $env:VCPKG_DEFAULT_TRIPLET = "arm64-windows"
} elseif ($IsMacOS -and $qtVersion.Major -eq 5) {
    $env:VCPKG_DEFAULT_TRIPLET = "x64-osx"
}

# Get our dependencies using vcpkg!
if ($IsWindows) {
    $vcpkgexec = "vcpkg.exe"
} else {
    $vcpkgexec = "vcpkg"
}

function InstallPackages() {
    # dav1d for win32 not marked supported due to build issues in the past but seems to be fine now
    $allowUnsupported = $env:VCPKG_DEFAULT_TRIPLET -eq 'x86-windows' ? '--allow-unsupported' : $null

    # Build without x265 (only needed for encoding), but this breaks the Linux build
    $libheif = $IsLinux ? 'libheif' : 'libheif[core]'

    & "$env:VCPKG_ROOT/$vcpkgexec" install $allowUnsupported libjxl openexr zlib libraw libavif[dav1d] $libheif
}

InstallPackages

# Build x64-osx dependencies separately--we'll have to combine stuff later.
if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    $env:VCPKG_DEFAULT_TRIPLET = "x64-osx"
    InstallPackages
}

$env:VCPKG_DEFAULT_TRIPLET = $null
