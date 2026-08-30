param([string]$Suite = "")

# Headless UI Development Harness wrapper. See docs/ui-harness.md.
# Usage:  powershell -ExecutionPolicy Bypass -File tools\ui_harness\run_ui_harness.ps1 [-Suite <name>]

$engine = "D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe"
$project = "G:\godotproject\darkrpg"

$godotArgs = @(
    "--headless",
    "--path", $project,
    "--script", "res://tools/ui_harness/ui_harness_runner.gd"
)
if ($Suite -ne "") {
    $godotArgs += @("++", "--suite", $Suite)
}

& $engine @godotArgs
exit $LASTEXITCODE
