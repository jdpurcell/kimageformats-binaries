#!/usr/bin/env pwsh

# Install vcpkg if we don't already have it
if ($env:VCPKG_ROOT -eq $null) {
  git clone https://github.com/microsoft/vcpkg
  if ($IsWindows) {
      vcpkg/bootstrap-vcpkg.bat
  } else {
      vcpkg/bootstrap-vcpkg.sh
  }
  $env:VCPKG_ROOT = "$PWD/vcpkg/"
}

if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE\pwsh\vcvars.ps1"
    
    # Use environment variable to detect if we're building for 64-bit or 32-bit Windows 
    if ([Environment]::Is64BitOperatingSystem -and ($env:forceWin32 -ne 'true')) {
        $env:VCPKG_DEFAULT_TRIPLET = "x64-windows"
    }
} elseif ($IsMacOS) {
    # Makes things more reproducible for testing on M1 machines
    $env:VCPKG_DEFAULT_TRIPLET = "x64-osx"
}

# Get our dependencies using vcpkg!
if ($IsWindows) {
    $vcpkgexec = "vcpkg.exe"
} else {
    $vcpkgexec = "vcpkg"
}
& "$env:VCPKG_ROOT/$vcpkgexec" install --keep-going libjxl libheif libavif openexr libraw


# Build m1 guys and combine them to get universal binaries from this
if ($IsMacOS) {
    & "$env:VCPKG_ROOT/$vcpkgexec" install --keep-going libjxl:arm64-osx libheif:arm64-osx libavif:arm64-osx openexr:arm64-osx libraw:arm64-osx
}

