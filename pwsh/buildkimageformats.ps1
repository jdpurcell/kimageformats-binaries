#!/usr/bin/env pwsh

$qtVersion = [version](qmake -query QT_VERSION)
Write-Host "Detected Qt version $qtVersion"

$kfGitRef =
    $qtVersion -ge [version]'6.8.0' ? 'v6.22.0' :
    $qtVersion -ge [version]'6.7.0' ? 'v6.17.0' :
    $(throw 'Unsupported Qt version.')
$kfMajorVer = 6
$kimgLibExt =
    $IsWindows ? '.dll' :
    $IsMacOS ? '.dylib' :
    '.so'

# Clone
git clone https://invent.kde.org/frameworks/kimageformats.git KImageFormats
cd KImageFormats
git checkout $kfGitRef

# Patch CMakeLists to work with vcpkg's libraw, bypassing KImageFormats' FindLibRaw module.
# The patch also specifies the thread-safe version of libraw.
patch CMakeLists.txt "../util/kimageformats$kfMajorVer-find-libraw-vcpkg.patch"
rm "cmake/find-modules/FindLibRaw.cmake"

# Patch CMakeLists to work with vcpkg's jxrlib, bypassing KImageFormats' FindLibJXR module.
patch CMakeLists.txt "../util/kimageformats$kfMajorVer-find-jxrlib-vcpkg.patch"
rm "cmake/find-modules/FindLibJXR.cmake"

if ($IsLinux) {
    # On Linux, ECM requests errors to be treated as warnings, which we need to suppress to build successfully
    patch src/imageformats/CMakeLists.txt "../util/kimageformats$kfMajorVer-no-fatal-warnings-jxrlib-linux.patch"
}

# Dependencies
if ($IsWindows) {
    & "$env:GITHUB_WORKSPACE/pwsh/vcvars.ps1"

    choco install pkgconfiglite

    # Workaround for https://developercommunity.visualstudio.com/t/10664660
    $env:CXXFLAGS += " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR"
    $env:CFLAGS += " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR"
}

& "$env:GITHUB_WORKSPACE/pwsh/get-vcpkg-deps.ps1" $kfGitRef
& "$env:GITHUB_WORKSPACE/pwsh/buildecm.ps1" $kfGitRef
& "$env:GITHUB_WORKSPACE/pwsh/buildkarchive.ps1" $kfGitRef

if ($IsMacOS) {
    $argDeviceArchs =
        $env:buildArch -eq 'X64' ? '-DCMAKE_OSX_ARCHITECTURES=x86_64' :
        $env:buildArch -in 'Arm64', 'Universal' ? '-DCMAKE_OSX_ARCHITECTURES=arm64' :
        $null
}

# Build kimageformats
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/installed" -DKIMAGEFORMATS_JXL=ON -DKIMAGEFORMATS_HEIF=ON -DKIMAGEFORMATS_JXR=ON -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_INSTALLED_DIR="$env:VCPKG_ROOT/installed-$env:VCPKG_DEFAULT_TRIPLET" $argDeviceArchs .

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

    [Environment]::SetEnvironmentVariable("KF${kfMajorVer}Archive_DIR", [Environment]::GetEnvironmentVariable("KF${kfMajorVer}Archive_DIR_INTEL"))

    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/installed_intel" -DKIMAGEFORMATS_JXL=ON -DKIMAGEFORMATS_HEIF=ON -DKIMAGEFORMATS_JXR=ON -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_INSTALLED_DIR="$env:VCPKG_ROOT/installed-x64-osx" -DVCPKG_TARGET_TRIPLET="x64-osx" -DCMAKE_OSX_ARCHITECTURES="x86_64" .

    ninja
    ninja install

    Write-Host "Combining kimageformats binaries to universal"

    $prefix = "installed/lib/plugins/imageformats"
    $prefix_intel = "installed_intel/lib/plugins/imageformats"

    # Combine the two binaries and copy them to the output folder
    $files = Get-ChildItem "$prefix" -Recurse -Filter "*$kimgLibExt"
    foreach ($file in $files) {
        $name = $file.Name
        lipo -create "$file" "$prefix_intel/$name" -output "$prefix_out/$name"
        lipo -info "$prefix_out/$name"
    }

    # Combine karchive binaries too and send them to output
    $name = "libKF${kfMajorVer}Archive.$kfMajorVer.dylib"
    lipo -create "karchive/installed/lib/$name" "karchive/installed_intel/lib/$name" -output "$prefix_out/$name"
    lipo -info "$prefix_out/$name"
} else {
    # Copy binaries from installed to output folder
    $files = Get-ChildItem "installed/lib" -Recurse -Filter "*$kimgLibExt"
    foreach ($file in $files) {
        cp $file $prefix_out
    }

    # Copy karchive stuff to output as well
    if ($IsWindows) {
        cp karchive/bin/*.dll $prefix_out
        # Also copy all the vcpkg DLLs on windows, since it's apparently not static by default
        cp "$env:VCPKG_ROOT/installed-$env:VCPKG_DEFAULT_TRIPLET/$env:VCPKG_DEFAULT_TRIPLET/bin/*.dll" $prefix_out
    } elseif ($IsMacOS) {
        cp karchive/bin/libKF${kfMajorVer}Archive.$kfMajorVer.dylib $prefix_out
    } else {
        cp karchive/bin/libKF${kfMajorVer}Archive.so.$kfMajorVer $prefix_out
    }
}

# Fix linking on macOS
if ($IsMacOS) {
    $karchLibName = "libKF${kfMajorVer}Archive.$kfMajorVer"
    foreach ($installDirName in @('installed') + ($IsMacOS -and $env:buildArch -eq 'Universal' ? @('installed_intel') : @())) {
        $oldValue = "$(Get-Location)/karchive/$installDirName/lib/$karchLibName.dylib"
        $newValue = "@rpath/$karchLibName.dylib"
        install_name_tool -id $newValue "$prefix_out/$karchLibName.dylib"
        foreach ($kimgLibName in @('kimg_kra', 'kimg_ora')) {
            install_name_tool -change $oldValue $newValue "$prefix_out/$kimgLibName$kimgLibExt"
        }
    }
}

# Fix linking on Linux
if ($IsLinux) {
    patchelf --set-rpath '$ORIGIN' "$prefix_out/libKF${kfMajorVer}Archive.so.$kfMajorVer"

    $files = Get-ChildItem "$prefix_out" -Recurse -Filter "kimg_*$kimgLibExt"
    foreach ($file in $files) {
        patchelf --set-rpath '$ORIGIN/../../lib' $file
    }
}

if ($IsWindows) {
    Write-Host "`nDetecting plugin dependencies..."
    $kimgDeps = & "$env:GITHUB_WORKSPACE/pwsh/scankimgdeps.ps1" $prefix_out

    # Remove unnecessary files
    $files = Get-ChildItem $prefix_out
    foreach ($file in $files) {
        $name = $file.Name
        $found = $name -like 'kimg_*.dll' -or $name -in $kimgDeps
        if (-not $found) {
            Write-Host "Deleting $name"
            Remove-Item -Path $file.FullName
        }
    }
}
