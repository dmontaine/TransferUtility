# Build SD Transfer Utility for Windows (win32 widgetset, 64-bit).
#
#   powershell -ExecutionPolicy Bypass -File WindowsVersion\build.ps1
#
# Builds bin\sd-transfer.exe and bin\sd-askpass.exe at the repository root from the
# shared source in src\, then strips debug information.  Set LAZARUS_DIR if Lazarus
# is not in C:\lazarus.

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
