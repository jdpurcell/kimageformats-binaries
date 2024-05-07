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
    # Remove this package on macOS because it causes problems
    brew uninstall --ignore-dependencies webp # Avoid linking to homebrew stuff later
} else {
    # (and bonus dependencies)
    sudo apt-get install nasm libxi-dev libgl1-mesa-dev libglu1-mesa-dev mesa-common-dev libxrandr-dev libxxf86vm-dev
}

if ($IsWindows -and [Environment]::Is64BitOperatingSystem -and $env:forceWin32 -eq 'true') {
    $env:VCPKG_DEFAULT_TRIPLET = "x86-windows"
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
    # libavif includes aom which refuses to build on x86-windows despite trying workarounds mentioned in https://github.com/microsoft/vcpkg/issues/28389
    $libAvif = $env:VCPKG_DEFAULT_TRIPLET -ne "x86-windows" ? "libavif[aom]" : $null
    # No point to building libheif on mac since Qt has built-in support for HEIF on macOS. Also, this avoids CI problems.
    $libHeif = -not $IsMacOS ? "libheif" : $null

    & "$env:VCPKG_ROOT/$vcpkgexec" install libjxl openexr zlib libraw $libAvif $libHeif
}

InstallPackages

# Build x64-osx dependencies separately--we'll have to combine stuff later.
if ($env:universalBinary -eq 'true') {
    $env:VCPKG_DEFAULT_TRIPLET = "x64-osx"
    InstallPackages
}

$env:VCPKG_DEFAULT_TRIPLET = $null
