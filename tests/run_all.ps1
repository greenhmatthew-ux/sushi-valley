# Runs every headless test suite and reports a single pass/fail.
#
#   powershell -File tests/run_all.ps1
#
# Each suite is its own SceneTree script (quit code 0 = pass). Godot's shutdown
# leak/RID warnings are filtered so real output stays readable.

# NOT "Stop": Godot writes shutdown warnings to stderr, and with 2>&1 on a native
# exe PowerShell 5.1 turns each stderr line into a terminating error. Pass/fail is
# read from $LASTEXITCODE (each suite quits non-zero on failure) instead.
$ErrorActionPreference = "Continue"
$godot = "C:\Users\curby\Godot\Godot_v4.7.1-stable_win64_console.exe"
$project = Split-Path -Parent $PSScriptRoot
$suites = @(
	"smoke_db", "smoke_world", "test_srs", "test_learning",
	"test_lesson_gate", "test_recall_loop", "test_inventory", "test_combat",
	"test_save", "test_transitions", "test_quest", "test_speech", "test_teacher_npc", "test_sign_post", "test_combat_encounter",
	"smoke_autoloads"
)
$noise = "leaked|RID alloc|still in use|_free_rids|at: cleanup|core/io/resource|Godot Engine v|OpenGL API"

$failed = @()
foreach ($s in $suites) {
	Write-Host "===== $s =====" -ForegroundColor Cyan
	& $godot --headless --path $project --script "res://tests/$s.gd" 2>&1 |
		Select-String -NotMatch $noise |
		ForEach-Object { $_.Line }
	if ($LASTEXITCODE -ne 0) { $failed += $s }
	Write-Host ""
}

if ($failed.Count -eq 0) {
	Write-Host "ALL SUITES PASSED ($($suites.Count))" -ForegroundColor Green
	exit 0
} else {
	Write-Host "FAILED SUITES: $($failed -join ', ')" -ForegroundColor Red
	exit 1
}
