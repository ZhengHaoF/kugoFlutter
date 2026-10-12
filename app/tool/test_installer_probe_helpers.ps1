$ErrorActionPreference = "Stop"
. "$PSScriptRoot/installer_probe_helpers.ps1"
function Assert-Equal($Actual, $Expected, [string]$Message) {
  if ($Actual -ne $Expected) { throw "$Message : expected=$Expected actual=$Actual" }
}
$state = @{ Calls = 0; Sleeps = 0; Present = $true }
$exists = { param($item) $state.Present }.GetNewClosure()
$remove = {
  param($item)
  $state.Calls++
  if ($state.Calls -lt 3) { throw "simulated font lock" }
  $state.Present = $false
}.GetNewClosure()
$sleep = { param($delay) $state.Sleeps++ }.GetNewClosure()
Assert-Equal (Remove-KugoProbeDirectory -Path "fixture" -Attempts 5 -ExistsAction $exists -RemoveAction $remove -SleepAction $sleep) $true "transient locks recover"
Assert-Equal $state.Calls 3 "removal retried"
Assert-Equal $state.Sleeps 2 "retry delay used"
Write-Output "PASS transient font lock retry"

$state.Present = $true
$alwaysLocked = { param($item) throw "simulated persistent lock" }
Assert-Equal (Remove-KugoProbeDirectory -Path "fixture" -Attempts 2 -ExistsAction $exists -RemoveAction $alwaysLocked -SleepAction $sleep) $false "persistent lock is bounded"
Write-Output "PASS persistent font lock is bounded"

$original = $null
try {
  try { throw "PRIMARY_ACCEPTANCE_ERROR" }
  finally { $null = Remove-KugoProbeDirectory -Path "fixture" -Attempts 2 -ExistsAction $exists -RemoveAction $alwaysLocked -SleepAction $sleep }
} catch { $original = $_.Exception.Message }
Assert-Equal $original "PRIMARY_ACCEPTANCE_ERROR" "cleanup preserves the primary error"
Write-Output "PASS cleanup does not mask acceptance failure"

$process = [pscustomobject]@{ Id = 123; HasExited = $false; Waited = $false; Stopped = $false; ExitResult = $true }
$process | Add-Member ScriptMethod Refresh { }
$process | Add-Member ScriptMethod WaitForExit { param($timeout) $this.Waited = $true; return $this.ExitResult }
$stop = { param($id) $process.Stopped = $true }.GetNewClosure()
Stop-KugoProbeProcess -Process $process -StopAction $stop
Assert-Equal $process.Stopped $true "owned process stopped"
Assert-Equal $process.Waited $true "exit awaited before filesystem cleanup"
Write-Output "PASS process exit awaited"

$process.HasExited = $true
$process.Stopped = $false
$process.Waited = $false
Stop-KugoProbeProcess -Process $process -StopAction $stop
Assert-Equal $process.Stopped $false "exited process is not killed"
Assert-Equal $process.Waited $true "already exited process reaped"
Write-Output "PASS exited process handled"

$process.ExitResult = $false
$timedOut = $false
try { Stop-KugoProbeProcess -Process $process -StopAction $stop } catch { $timedOut = $true }
Assert-Equal $timedOut $true "exit timeout fails explicitly"
Write-Output "PASS process timeout is reported"
