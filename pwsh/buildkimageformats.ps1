#!/usr/bin/env pwsh

$qtVersion = [version]((qmake --version -split '\n')[1] -split ' ')[3]
Write-Host "Detected Qt Version $qtVersion"

$kde_vers = $qtVersion -ge [version]'6.5.0' ? 'v6.6.0' : 'v5.116.0'
$kfMajorVer = $kde_vers -like 'v5.*' ? 5 : 6
$macKimgLibExt = $kfMajorVer -ge 6 ? '.dylib' : '.so'

# Clone
git clone https://invent.kde.org/frameworks/kimageformats.git KImageFormats
cd KImageFormats
git checkout $kde_vers

# Apply patch to cmake file for vcpkg libraw
if (-Not $IsWindows) {
    patch CMakeLists.txt "../util/kimageformats$kfMajorVer-find-libraw-vcpkg.patch"
}

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

& "$env:GITHUB_WORKSPACE/pwsh/get-vcpkg-deps.ps1"
& "$env:GITHUB_WORKSPACE/pwsh/buildecm.ps1" $kde_vers
& "$env:GITHUB_WORKSPACE/pwsh/buildkarchive.ps1" $kde_vers

# Resolve pthread error on linux
if (-Not $IsWindows) {
    $env:CXXFLAGS += ' -pthread'
}

$argQt6 = $qtVersion.Major -eq 6 ? '-DBUILD_WITH_QT6=ON' : $null
if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -in 'Arm64', 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $null
}

# Build kimageformats
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/installed" -DKIMAGEFORMATS_JXL=ON -DKIMAGEFORMATS_HEIF=ON $argQt6 -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" $argDeviceArchs .

ninja
ninja install

# Location of actual plugin files
$prefix_out = "output"

# Make output folder
mkdir -p $prefix_out

# Build intel version as well and macos and lipo them together
if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    Write-Host "Building intel binaries"

    rm -rf CMakeFiles/
    rm -rf CMakeCache.txt

    [Environment]::SetEnvironmentVariable("KF$($kfMajorVer)Archive_DIR", [Environment]::GetEnvironmentVariable("KF$($kfMajorVer)Archive_DIR_INTEL"))

    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/installed_intel" -DKIMAGEFORMATS_JXL=ON -DKIMAGEFORMATS_HEIF=ON $argQt6 -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET="x64-osx" -DCMAKE_OSX_ARCHITECTURES="x86_64" .

    ninja
    ninja install

    Write-Host "Combining kimageformats binaries to universal"

    $prefix = "installed/lib/plugins/imageformats"
    $prefix_intel = "installed_intel/lib/plugins/imageformats"

    # Combine the two binaries and copy them to the output folder
    $files = Get-ChildItem "$prefix" -Recurse -Filter "*$macKimgLibExt"
    foreach ($file in $files) {
        $name = $file.Name
        lipo -create "$file" "$prefix_intel/$name" -output "$prefix_out/$name"
        lipo -info "$prefix_out/$name"
    }

    # Combine karchive binaries too and send them to output
    $name = "libKF$($kfMajorVer)Archive.$($kfMajorVer).dylib"
    lipo -create "karchive/installed/lib/$name" "karchive/installed_intel/lib/$name" -output "$prefix_out/$name"
    lipo -info "$prefix_out/$name"
} else {
    # Copy binaries from installed to output folder
    $files = dir ./installed/ -recurse | where {$_.extension -in ".dylib",".dll",".so"}
    foreach ($file in $files) {
        cp $file $prefix_out
    }

    # Copy karchive stuff to output as well
    if ($IsWindows) {
        cp karchive/bin/*.dll $prefix_out
        # Also copy all the vcpkg DLLs on windows, since it's apparently not static by default
        cp "$env:VCPKG_ROOT/installed/$env:VCPKG_DEFAULT_TRIPLET/bin/*.dll" $prefix_out
    } elseif ($IsMacOS) {
        cp karchive/bin/libKF$($kfMajorVer)Archive.$($kfMajorVer).dylib $prefix_out
    } else {
        $libLoc = Split-Path -Path (Get-Childitem -Include "libKF$($kfMajorVer)Archive.so.$($kfMajorVer)" -Recurse -ErrorAction SilentlyContinue)[0]
        [Environment]::SetEnvironmentVariable("KF$($kfMajorVer)LibLoc", $libLoc)
        cp $libLoc/* $prefix_out
    }
}

# Fix linking on macOS
if ($IsMacOS) {
    $karchLibName = "libKF$($kfMajorVer)Archive.$($kfMajorVer)"
    $libDirName = $kfMajorVer -ge 6 ? 'lib' : '' # empty name results in double slash in path which is intentional
    foreach ($installDirName in @('installed') + ($IsMacOS -and $env:buildArch -eq 'Universal' ? @('installed_intel') : @())) {
        $oldValue = "$(Get-Location)/karchive/$installDirName/$libDirName/$karchLibName.dylib"
        $newValue = "@rpath/$karchLibName.dylib"
        install_name_tool -id $newValue "$prefix_out/$karchLibName.dylib"
        foreach ($kimgLibName in @('kimg_kra', 'kimg_ora')) {
            install_name_tool -change $oldValue $newValue "$prefix_out/$kimgLibName$macKimgLibExt"
        }
    }
}

if ($IsWindows) {
    Write-Host "`nDetecting plugin dependencies..."
    & "$env:GITHUB_WORKSPACE/pwsh/scankimgdeps.ps1" $prefix_out
}
