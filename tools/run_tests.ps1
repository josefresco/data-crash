# Runs the headless test suites in parallel and prints one table.
#
#   pwsh tools/run_tests.ps1                      # every pass/fail suite
#   pwsh tools/run_tests.ps1 flow arsenal         # just these (the _test suffix is optional)
#   pwsh tools/run_tests.ps1 -Jobs 6 -Retries 0
#
# It imports once first (and stops on a script error), then runs up to -Jobs
# suites at a time. A suite passes when it prints "0 failure(s)": exit code 139
# after that line is the known engine crash on shutdown, not a failure. A
# failed suite is run again up to -Retries times; one that passes on a retry
# is reported as FLAKY with the checks that failed the first time. Full logs
# go to tests/output/logs/<suite>.log. Exit code: 0 if nothing failed.

[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Suites,
  [int]$Jobs = 4,
  [int]$Retries = 1,
  [int]$TimeoutSeconds = 420
)

$all = @("smoke", "defense", "units", "weapons", "boss", "activism", "arsenal", "stealth",
  "district2", "river", "bosses", "flow", "save")
if (-not $Suites -or $Suites.Count -eq 0) { $Suites = $all }
$Suites = $Suites | ForEach-Object { ($_ -replace "_test$", "") }

$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$logs = Join-Path $root "tests\output\logs"
New-Item -ItemType Directory -Force $logs | Out-Null

$started = Get-Date
$import = & $godot --headless --path $root --import 2>&1 | Out-String
if ($import -match "SCRIPT ERROR") {
  ($import -split "`n") | Select-String "SCRIPT ERROR" -Context 0, 3 | ForEach-Object { Write-Host $_ }
  Write-Host "Import found script errors: no suites were run."
  exit 2
}

$results = $Suites | ForEach-Object -ThrottleLimit $Jobs -Parallel {
  $suite = $_
  $log = Join-Path $using:logs "$suite.log"
  $firstFails = @()
  $status = "FAIL"
  $attempts = 0
  $seconds = 0.0
  $fails = @()
  while ($attempts -le $using:Retries) {
    $attempts++
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $job = Start-Job -ScriptBlock {
      param($exe, $path, $scene)
      & $exe --headless --fixed-fps 60 --path $path "res://tests/$scene.tscn" 2>&1 | Out-String
    } -ArgumentList $using:godot, $using:root, "${suite}_test"
    $done = Wait-Job $job -Timeout $using:TimeoutSeconds
    $text = if ($done) { Receive-Job $job } else { "TIMEOUT after $($using:TimeoutSeconds)s" }
    if (-not $done) { Stop-Job $job }
    Remove-Job $job -Force
    $seconds += $clock.Elapsed.TotalSeconds
    Set-Content -Path $log -Value $text -Encoding utf8
    $fails = @(($text -split "`n") | Where-Object { $_ -match "^FAIL" } | ForEach-Object { $_.Trim() })
    if ($text -match "(?m)^0 failure\(s\)") {
      $status = if ($attempts -eq 1) { "pass" } else { "FLAKY" }
      break
    }
    if (-not $done) { $fails = @("timed out") }
    if ($attempts -eq 1) { $firstFails = $fails }
  }
  [pscustomobject]@{
    Suite = $suite; Status = $status; Seconds = [math]::Round($seconds, 0); Runs = $attempts
    Failed = if ($status -eq "pass") { @() } elseif ($status -eq "FLAKY") { $firstFails } else { $fails }
  }
}

$results | Sort-Object Suite | Format-Table Suite, Status, Seconds, Runs -AutoSize | Out-String | Write-Host
foreach ($result in ($results | Where-Object { $_.Status -ne "pass" } | Sort-Object Suite)) {
  Write-Host "$($result.Suite) ($($result.Status)):"
  $result.Failed | Select-Object -First 8 | ForEach-Object { Write-Host "  $_" }
}
$wall = [math]::Round(((Get-Date) - $started).TotalSeconds, 0)
$sum = ($results | Measure-Object Seconds -Sum).Sum
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$flaky = @($results | Where-Object { $_.Status -eq "FLAKY" }).Count
Write-Host "$($results.Count) suites in ${wall}s wall (${sum}s of suite time): $failed failed, $flaky flaky."
exit ([int]($failed -gt 0))
