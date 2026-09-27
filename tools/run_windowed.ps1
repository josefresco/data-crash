# Runs a windowed test scene (screenshots, perf probes) without stealing focus.
#
#   pwsh tools/run_windowed.ps1 res://tests/gallery.tscn only=structures
#
# Arguments after the scene go to the scene (the script adds Godot's "--";
# PowerShell would swallow a literal one). Godot has no CLI flag for this, so
# a temporary override.cfg (git-ignored) sets display/window/size/no_focus
# for the run and is removed afterwards. Don't launch the game from this
# folder while it runs: it would pick up the override too.

if ($args.Count -lt 1) {
  Write-Error "usage: run_windowed.ps1 <res://scene.tscn> [scene args...]"
  exit 2
}
$scene = $args[0]
$sceneArgs = @()
if ($args.Count -gt 1) {
  $sceneArgs = @("--") + $args[1..($args.Count - 1)]
}

$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
$override = Join-Path $root "override.cfg"

if (Test-Path $override) {
  Write-Error "override.cfg already exists (another windowed run?). Remove it first."
  exit 1
}

@"
[display]

window/size/no_focus=true
"@ | Set-Content -Path $override -Encoding utf8NoBOM

$code = 1
try {
  & $godot --path $root $scene @sceneArgs
  $code = $LASTEXITCODE
} catch {
  Write-Error $_
} finally {
  Remove-Item -Path $override -Force -ErrorAction SilentlyContinue
}
exit $code
