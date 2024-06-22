using namespace System.Runtime.InteropServices

if ([RuntimeInformation]::OSArchitecture -ne [Architecture]::X64) {
    throw 'Unsupported host architecture.'
}

$arch =
    $env:buildArch -eq 'X64' ? 'x64' :
    $env:buildArch -eq 'X86' ? 'x64_x86' :
    $env:buildArch -eq 'Arm64' ? 'x64_arm64' :
    $null
if (-not $arch) {
    throw 'Unsupported build architecture.'
}

$path = Resolve-Path "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Auxiliary\Build" | Select-Object -ExpandProperty Path

cmd.exe /c "call `"$path\vcvarsall.bat`" $arch && set > %temp%\vcvars.txt"

$exclusions = @('VCPKG_ROOT')
Get-Content "$env:temp\vcvars.txt" | Foreach-Object {
    if ($_ -match "^(.*?)=(.*)$" -and $matches[1] -notin $exclusions) {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
    }
}
