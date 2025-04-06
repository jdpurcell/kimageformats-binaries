#!/usr/bin/env pwsh

$kfGitRef = $args[0]

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
    # Uninstall these, otherwise the heif plugin could reference them and
    # end up not working, but silence stderr in case they aren't present
    foreach ($pkgName in @('webp', 'aom', 'libvmaf')) {
        brew uninstall --ignore-dependencies $pkgName 2>$null
    }
} else {
    # (and bonus dependencies)
    sudo apt-get install nasm libxi-dev libgl1-mesa-dev libglu1-mesa-dev mesa-common-dev libxrandr-dev libxxf86vm-dev
}

# Set default triplet
if ($IsWindows) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-windows' :
        $env:buildArch -eq 'X86' ? 'x86-windows-static-md' :
        $env:buildArch -eq 'Arm64' ? 'arm64-windows-static-md' :
        $null
} elseif ($IsMacOS) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-osx' :
        $env:buildArch -in 'Arm64', 'Universal' ? 'arm64-osx' :
        $null
} elseif ($IsLinux) {
    $env:VCPKG_DEFAULT_TRIPLET =
        $env:buildArch -eq 'X64' ? 'x64-linux' :
        $env:buildArch -eq 'Arm64' ? 'arm64-linux' :
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

# Create overlay triplet directory
$env:VCPKG_OVERLAY_TRIPLETS = "$env:GITHUB_WORKSPACE/vcpkg-overlay-triplets"
New-Item -ItemType Directory -Path $env:VCPKG_OVERLAY_TRIPLETS -Force

function WriteOverlayTriplet() {
    $srcPath = "$env:VCPKG_ROOT/triplets/$env:VCPKG_DEFAULT_TRIPLET.cmake"
    if (-not (Test-Path $srcPath)) {
        $srcPath = "$env:VCPKG_ROOT/triplets/community/$env:VCPKG_DEFAULT_TRIPLET.cmake"
    }
    $dstPath = "$env:VCPKG_OVERLAY_TRIPLETS/$env:VCPKG_DEFAULT_TRIPLET.cmake"
    Copy-Item -Path $srcPath -Destination $dstPath

    function AppendLine($value) {
        Add-Content -Path $dstPath -Value $value
    }

    # Ensure trailing newline is present
    AppendLine ''

    # Skip debug builds
    AppendLine 'set(VCPKG_BUILD_TYPE release)'

    if ($IsWindows) {
        # Workaround for https://developercommunity.visualstudio.com/t/10664660
        AppendLine 'string(APPEND VCPKG_CXX_FLAGS " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR")'
        AppendLine 'string(APPEND VCPKG_C_FLAGS " -D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR")'
    }
}

# Create overlay ports directory
$env:VCPKG_OVERLAY_PORTS = "$env:GITHUB_WORKSPACE/vcpkg-overlay-ports"
New-Item -ItemType Directory -Path $env:VCPKG_OVERLAY_PORTS -Force

function WriteOverlayPorts() {
    # Remove any existing files
    Remove-Item -Path "$env:VCPKG_OVERLAY_PORTS/*" -Recurse -Force

    function CopyBuiltinPort($name) {
        Copy-Item -Path "$env:VCPKG_ROOT/ports/$name" -Destination "$env:VCPKG_OVERLAY_PORTS" -Recurse
    }

    # Copy / modify ports here as needed
}

# Create vcpkg manifest directory
$vcpkgManifestDir = "$env:GITHUB_WORKSPACE/vcpkg-manifest"
New-Item -ItemType Directory -Path $vcpkgManifestDir -Force

function WriteManifest() {
    $manifest = @{
        'builtin-baseline' = $env:VCPKG_COMMIT_ID
        'dependencies' = @()
        'overrides' = @()
    }

    function AddDependency($name, $features = $null, $disableDefaultFeatures = $false) {
        $dependency = @{ 'name' = $name }
        if ($features) {
            $dependency['features'] = $features
        }
        if ($disableDefaultFeatures) {
            $dependency['default-features'] = $false
        }
        $manifest['dependencies'] += $dependency
    }

    function AddOverride($name, $version) {
        $manifest['overrides'] += @{ 'name' = $name; 'version' = $version }
    }

    AddDependency 'zlib'
    # AddDependency 'libjxl'
    # AddDependency 'openjpeg'
    # AddDependency 'openexr'
    # AddDependency 'libraw'
    # AddDependency 'libavif' @('dav1d')
    # AddDependency 'libheif' $null true

    $manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath "$vcpkgManifestDir/vcpkg.json"
}

function InstallPackages() {
    WriteOverlayTriplet

    WriteOverlayPorts

    WriteManifest

    # dav1d for win32 not marked supported due to build issues in the past but seems to be fine now
    $allowUnsupported = $env:VCPKG_DEFAULT_TRIPLET -like 'x86-windows*' ? '--allow-unsupported' : $null

    & "$env:VCPKG_ROOT/$vcpkgexec" install --x-manifest-root="$vcpkgManifestDir" --x-install-root="$env:VCPKG_ROOT/installed-$env:VCPKG_DEFAULT_TRIPLET" $allowUnsupported
}

InstallPackages

# Build x64-osx dependencies separately--we'll have to combine stuff later.
if ($IsMacOS -and $env:buildArch -eq 'Universal') {
    $mainTriplet = $env:VCPKG_DEFAULT_TRIPLET
    $env:VCPKG_DEFAULT_TRIPLET = 'x64-osx'

    InstallPackages

    $env:VCPKG_DEFAULT_TRIPLET = $mainTriplet
}
