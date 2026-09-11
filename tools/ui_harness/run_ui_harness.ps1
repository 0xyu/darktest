param(
    [string]$Suite = "",
    [switch]$Quiet,
    [switch]$List
)

# Headless UI Development Harness wrapper. See docs/ui-harness.md.
# Usage:  powershell -ExecutionPolicy Bypass -File tools\ui_harness\run_ui_harness.ps1 `
#             [-Suite <name>] [-Quiet] [-List]
#
#   -Suite <name>  run one suite only (name = suite file name without .gd)
#   -Quiet         print only SKIP / FAIL lines plus the one-line summary
#   -List          list the available suite names and exit

$engine = "D:\IDE\godotEngine\Godot_v4.7.2-stable_win64_console.exe"
$project = "G:\godotproject\darkrpg"

$godotArgs = @(
    "--headless",
    "--path", $project,
    "--script", "res://tools/ui_harness/ui_harness_runner.gd"
)
$userArgs = @()
if ($Suite -ne "") { $userArgs += @("--suite", $Suite) }
if ($Quiet) { $userArgs += "--quiet" }
if ($List) { $userArgs += "--list" }
if ($userArgs.Count -gt 0) {
    $godotArgs = $godotArgs + @("++") + $userArgs
}

& $engine @godotArgs
exit $LASTEXITCODE
