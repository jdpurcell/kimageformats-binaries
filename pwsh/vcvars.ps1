$arch = [Environment]::Is64BitOperatingSystem -and $env:forceWin32 -ne 'true' ? 'x64' : 'x64_x86'
$path = Resolve-Path "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Auxiliary\Build" | select -ExpandProperty Path

cmd.exe /c "call `"$path\vcvarsall.bat`" $arch && set > %temp%\vcvars.txt"

$exclusions = @('VCPKG_ROOT')
Get-Content "$env:temp\vcvars.txt" | Foreach-Object {
  if ($_ -match "^(.*?)=(.*)$" -and $matches[1] -notin $exclusions) {
    [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
  }
}
