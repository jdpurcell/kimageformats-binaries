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
# Remove this package on macOS because it caues problems
    brew uninstall --ignore-dependencies webp # Avoid linking to homebrew stuff later
} else {
    # (and bonus dependencies)
    sudo apt-get install nasm libxi-dev libgl1-mesa-dev libglu1-mesa-dev mesa-common-dev libxrandr-dev libxxf86vm-dev
}

# Set up prefixes
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE\pwsh\vcvars.ps1"
    
    # Use environment variable to detect if we're building for 64-bit or 32-bit Windows 
    if ([Environment]::Is64BitOperatingSystem -and ($env:forceWin32 -ne 'true')) {
        $env:VCPKG_DEFAULT_TRIPLET = "x64-windows"
    } else {
        $env:VCPKG_DEFAULT_TRIPLET = "x86-windows"
    }
} elseif ($IsMacOS) {
    # Makes things more reproducible for testing on M1 machines
    $env:VCPKG_DEFAULT_TRIPLET = "x64-osx"
}

# Set up overlay triplets
$defaultTripletDir = "$env:VCPKG_ROOT/triplets"
$overlayTripletDir = "$env:GITHUB_WORKSPACE/triplets-overlay"
New-Item -ItemType Directory -Path $overlayTripletDir -Force
function WriteOverlayTriplet {
    $srcPath = "$defaultTripletDir/$env:VCPKG_DEFAULT_TRIPLET.cmake"
    $dstPath = "$overlayTripletDir/$env:VCPKG_DEFAULT_TRIPLET.cmake"
    Copy-Item -Path $srcPath -Destination $dstPath -Force
    Add-Content -Path $dstPath -Value $args[0]
}
if ($env:VCPKG_DEFAULT_TRIPLET -eq "x86-windows") {
    # Attempted workaround for https://github.com/microsoft/vcpkg/issues/28389
    # Tried setting VCPKG_MAX_CONCURRENCY inside the overlay file too, but seemed 
    # like it wasn't taking effect, so that part gets set via PowerShell later.
    # None of this ended up fixing the problem unfortunately.
    WriteOverlayTriplet @"
if(PORT MATCHES "aom")
    string(APPEND VCPKG_C_FLAGS " /Zm2000 ")
    string(APPEND VCPKG_CXX_FLAGS " /Zm2000 ")
endif()
"@
}

# Get our dependencies using vcpkg!
if ($IsWindows) {
    $vcpkgexec = "vcpkg.exe"
} else {
    $vcpkgexec = "vcpkg"
}

$env:VCPKG_MAX_CONCURRENCY = "1"
& "$env:VCPKG_ROOT/$vcpkgexec" install --keep-going --overlay-triplets $overlayTripletDir libavif
$env:VCPKG_MAX_CONCURRENCY = ""

& "$env:VCPKG_ROOT/$vcpkgexec" install --keep-going --overlay-triplets $overlayTripletDir libjxl openexr zlib libraw

# No point to building libheif on mac since Qt has built-in support for HEIF on macOS. Also, this avoids CI problems.
if (-Not $IsMacOS) {
    & "$env:VCPKG_ROOT/$vcpkgexec" install --overlay-triplets $overlayTripletDir libheif
}

# Build arm64-osx dependencies separately--we'll have to combine stuff later.
if ($env:universalBinary) {
    & "$env:VCPKG_ROOT/$vcpkgexec" install --keep-going --overlay-triplets $overlayTripletDir libjxl:arm64-osx libavif:arm64-osx openexr:arm64-osx zlib:arm64-osx libraw:arm64-osx
}
