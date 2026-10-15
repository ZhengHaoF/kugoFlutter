# Shared bounded teardown helpers. Only processes/paths owned by the probe are used.
function Stop-OvertoneProbeProcess {
  param(
    [object]$Process,
    [int]$TimeoutMilliseconds = 10000,
    [scriptblock]$StopAction = { param($id) Stop-Process -Id $id -Force -ErrorAction Stop }
  )
  if ($null -eq $Process) { return }
  $Process.Refresh()
  if (-not $Process.HasExited) {
    & $StopAction $Process.Id | Out-Null
  }
  if (-not $Process.WaitForExit($TimeoutMilliseconds)) {
    throw "Probe application did not exit within the teardown deadline"
  }
}

function Remove-OvertoneProbeDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Attempts = 40,
    [int]$DelayMilliseconds = 250,
    [scriptblock]$ExistsAction = { param($item) Test-Path -LiteralPath $item },
    [scriptblock]$RemoveAction = { param($item) Remove-Item -LiteralPath $item -Recurse -Force -ErrorAction Stop },
    [scriptblock]$SleepAction = { param($delay) Start-Sleep -Milliseconds $delay }
  )
  for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
    if (-not (& $ExistsAction $Path)) { return $true }
    try {
      & $RemoveAction $Path | Out-Null
      if (-not (& $ExistsAction $Path)) { return $true }
    } catch {
      # Font caches can retain handles briefly after the application has exited.
    }
    if ($attempt + 1 -lt $Attempts) {
      & $SleepAction $DelayMilliseconds | Out-Null
    }
  }
  return $false
}
