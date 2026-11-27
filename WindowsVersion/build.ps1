# Build SD Core Transfer Utility for Windows (win32 widgetset, 64-bit).
#
#   powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1
#   powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1 -Installer
#
# Builds bin\sd-transfer.exe and bin\sd-askpass.exe at the repository root from the
# shared source in src\, then strips debug information.  With -Installer it also
# compiles WindowsVersion\sd-transfer.iss with Inno Setup 6 into
# build\installer\transfer-utility-setup.exe, the version read from
# src\uModels.pas.  Set LAZARUS_DIR if Lazarus is not in C:\lazarus, and ISCC if
# ISCC.exe is not in one of the usual Inno Setup 6 folders.
#
# Close any running sd-transfer.exe first: Windows will not replace a running program.

param([switch] $Installer)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$LazDir = if ($env:LAZARUS_DIR) { $env:LAZARUS_DIR } else { 'C:\lazarus' }
$FpcBin = Get-ChildItem -Directory (Join-Path $LazDir 'fpc') |
  ForEach-Object { Join-Path $_.FullName 'bin\x86_64-win64' } |
  Where-Object { Test-Path (Join-Path $_ 'fpc.exe') } | Select-Object -First 1
if (-not $FpcBin) { throw "No FPC for x86_64-win64 under $LazDir\fpc" }
$Fpc = Join-Path $FpcBin 'fpc.exe'
$Strip = Join-Path $FpcBin 'strip.exe'
$LazBuild = Join-Path $LazDir 'lazbuild.exe'

if (Get-Process sd-transfer -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq (Join-Path $Root 'bin\sd-transfer.exe') }) {
  throw 'bin\sd-transfer.exe is running; close SD Core Transfer Utility and build again.'
}

$Bin = Join-Path $Root 'bin'
$AskpassUnits = Join-Path $Root 'build\askpass\x86_64-win64'
New-Item -ItemType Directory -Force $Bin, $AskpassUnits | Out-Null

Write-Host 'Building sd-askpass.exe'
& $Fpc -O2 "-FU$AskpassUnits" "-FE$Bin" "-o$(Join-Path $Bin 'sd-askpass.exe')" (Join-Path $Root 'src\sd-askpass.lpr')
if ($LASTEXITCODE -ne 0) { throw 'sd-askpass did not build' }

Write-Host 'Building sd-transfer.exe'
& $LazBuild "--lazarusdir=$LazDir" --ws=win32 (Join-Path $Root 'src\sdtransfer.lpi')
if ($LASTEXITCODE -ne 0) { throw 'sd-transfer did not build' }

# The Lazarus project keeps debug info for the IDE; the deliverable does not need it.
if (Test-Path $Strip) {
  & $Strip (Join-Path $Bin 'sd-transfer.exe') (Join-Path $Bin 'sd-askpass.exe')
}
Get-Item (Join-Path $Bin 'sd-transfer.exe'), (Join-Path $Bin 'sd-askpass.exe') |
  Format-Table Name, Length, LastWriteTime -AutoSize

if ($Installer) {
  $Iscc = $env:ISCC
  if (-not $Iscc) {
    $Iscc = @(
      (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
      (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
  }
  if (-not $Iscc) { throw 'Inno Setup 6 (ISCC.exe) was not found; set ISCC to its path.' }
  $Models = Get-Content (Join-Path $Root 'src\uModels.pas') -Raw
  if ($Models -notmatch "AppVersion\s*=\s*'([^']+)'") { throw 'No AppVersion in src\uModels.pas' }
  $Ver = $Matches[1]
  Write-Host "Building the installer for version $Ver"
  & $Iscc /Q "/DAppVer=$Ver" (Join-Path $PSScriptRoot 'sd-transfer.iss')
  if ($LASTEXITCODE -ne 0) { throw 'The installer did not build' }
  Get-Item (Join-Path $Root "build\installer\transfer-utility-setup.exe") |
    Format-Table Name, Length, LastWriteTime -AutoSize
}
