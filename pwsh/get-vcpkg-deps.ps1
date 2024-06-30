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

# Set default triplet
if ($IsWindows) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-windows' :
        $env:buildArch -eq 'X86' ? 'x86-windows' :
        $env:buildArch -eq 'Arm64' ? 'arm64-windows' :
        $null
} elseif ($IsMacOS) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-osx' :
        $env:buildArch -in 'Arm64', 'Universal' ? 'arm64-osx' :
        $null
} elseif ($IsLinux) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-linux' :
        $null
}
if (-not $env:VCPKG_DEFAULT_TRIPLET) {
    throw 'Unsupported build architecture.'
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
    $mainTriplet = $env:VCPKG_DEFAULT_TRIPLET
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-osx'

    InstallPackages

    $env:VCPKG_DEFAULT_TRIPLET = $mainTriplet
}
