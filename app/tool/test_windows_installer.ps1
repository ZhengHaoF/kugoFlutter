param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [Parameter(Mandatory = $true)][string]$SourceDirectory,
  [Parameter(Mandatory = $true)][string]$Report
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/installer_probe_helpers.ps1"
$installerPath = (Resolve-Path $Installer).Path
$source = (Resolve-Path $SourceDirectory).Path
$destination = Join-Path $env:RUNNER_TEMP ("overtone-installer-probe-" + [guid]::NewGuid())
function RunSetup([string]$Executable, [string[]]$SetupArguments) {
  $process = Start-Process $Executable -ArgumentList $SetupArguments -PassThru
  if (-not $process.WaitForExit(120000)) {
    $process.Kill()
    throw "Installer process timed out"
  }
  if ($process.ExitCode -ne 0) { throw "Installer process failed: $($process.ExitCode)" }
}
try {
  RunSetup $installerPath @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=`"$destination`"")
  foreach ($file in Get-ChildItem $source -File -Recurse -Force) {
    $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
    $installed = Join-Path $destination $relative
    if (-not (Test-Path $installed)) { throw "Missing installed file: $relative" }
    if ((Get-FileHash $file.FullName).Hash -ne (Get-FileHash $installed).Hash) {
      throw "Installed file hash mismatch: $relative"
    }
  }
  $iconReport = "$Report.icons"
  & "$PSScriptRoot/test_windows_app_icons.ps1" -Executable "$destination/overtone.exe" -Report $iconReport
  if (-not (Test-Path $iconReport)) { throw "Installed application startup/icon report missing" }
  "PASS install files and installed app startup" | Set-Content $Report -Encoding utf8
  $uninstallers = @(Get-ChildItem $destination -Filter "unins*.exe")
  if ($uninstallers.Count -ne 1) { throw "Missing or ambiguous uninstaller" }
  RunSetup $uninstallers[0].FullName @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
  if (Test-Path "$destination/overtone.exe") { throw "Application remains after uninstall" }
  "PASS uninstall" | Add-Content $Report -Encoding utf8
} catch {
  # Print the primary failure before cleanup, which must never replace it.
  Write-Error -ErrorRecord $_ -ErrorAction Continue
  throw
} finally {
  if (-not (Remove-OvertoneProbeDirectory -Path $destination)) {
    Write-Warning "Temporary probe directory is still locked after bounded cleanup; the runner will discard it: $destination"
  }
}
