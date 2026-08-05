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
# Godot binary: honour GODOT_EXE, then PATH, then common install spots, so the
# runner works on any machine without editing the script.
$godot = $env:GODOT_EXE
if (-not $godot) {
	$onPath = Get-Command "Godot*_console.exe", "godot.exe" -ErrorAction SilentlyContinue |
		Select-Object -First 1 -ExpandProperty Source
	$godot = $onPath
}
if (-not $godot) {
	$candidates = @(
		"$env:USERPROFILE\Godot\Godot_*_console.exe",
		"D:\Godot*\Godot_*_console.exe",
		"C:\Godot*\Godot_*_console.exe"
	)
	$godot = $candidates |
		ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } |
		Sort-Object Name -Descending |
		Select-Object -First 1 -ExpandProperty FullName
}
if (-not $godot -or -not (Test-Path -LiteralPath $godot)) {
	throw "Godot console exe not found. Set GODOT_EXE to its full path."
}
$project = Split-Path -Parent $PSScriptRoot
$suites = @(
	"smoke_db", "test_pronunciation_audio", "test_deck_audio", "test_audio_music", "smoke_world", "test_mountain_pass", "test_srs", "test_learning",
	"test_lesson_gate", "test_recall_loop", "test_recall_panel", "test_notebook_panel", "test_inventory", "test_combat",
	"test_save", "test_inventory_persistence", "test_farm", "test_weather", "test_fishing", "test_gathering", "test_transitions", "test_quest", "test_quest_journal", "test_activity_tracker", "test_quest_giver", "test_teacher_npc", "test_raid", "test_expedition", "test_expedition_room", "test_sign_post", "test_study_spot", "test_combat_encounter", "test_player_stats", "test_shop_haggle", "test_japanese_sourcing", "test_card_content", "test_bestiary",
	"test_ability_logic", "test_consumables", "test_crafting", "test_smithing_chain", "test_combat_panel", "test_input_hints", "test_world_map_graph", "test_player_menu", "test_session_summary", "test_toast_feed", "test_hud_review_cue", "test_objective_hud", "test_ui_fits", "test_door_signage", "test_world_art",
	"smoke_autoloads"
)
$noise = "leaked|RID alloc|still in use|_free_rids|at: cleanup|core/io/resource|Godot Engine v|OpenGL API"
$scriptFailure = "SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Failed loading resource"

$originalAppData = $env:APPDATA
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testAppData = [System.IO.Path]::GetFullPath(
	(Join-Path $tempRoot ("sushi-valley-tests-" + [System.Guid]::NewGuid().ToString("N")))
)
if (-not $testAppData.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
	$testAppData -eq $tempRoot) {
	throw "Refusing unsafe test APPDATA path: $testAppData"
}
New-Item -ItemType Directory -Path $testAppData | Out-Null

$failed = @()
try {
	# Save tests deliberately create and remove user://profile.json. Point Godot at a
	# unique APPDATA root so the real playthrough can never be touched by this runner.
	$env:APPDATA = $testAppData
	foreach ($s in $suites) {
		Write-Host "===== $s =====" -ForegroundColor Cyan
		# Capture before filtering. Godot can occasionally report a parser/compiler
		# failure while the SceneTree entry script still exits 0, so the native exit
		# code alone is not sufficient evidence that a suite actually loaded.
		$rawOutput = @(& $godot --headless --path $project --script "res://tests/$s.gd" 2>&1)
		$exitCode = $LASTEXITCODE
		$outputLines = @($rawOutput | ForEach-Object { $_.ToString() })
		$outputLines |
			Select-String -NotMatch $noise |
			ForEach-Object { $_.Line }
		$hadScriptFailure = $null -ne ($outputLines |
			Select-String -Pattern $scriptFailure | Select-Object -First 1)
		if ($exitCode -ne 0 -or $hadScriptFailure) { $failed += $s }
		Write-Host ""
	}
} finally {
	$env:APPDATA = $originalAppData
	$cleanupPath = [System.IO.Path]::GetFullPath($testAppData)
	if ($cleanupPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
		$cleanupPath -ne $tempRoot -and (Test-Path -LiteralPath $cleanupPath)) {
		Remove-Item -LiteralPath $cleanupPath -Recurse -Force
	}
}

if ($failed.Count -eq 0) {
	Write-Host "ALL SUITES PASSED ($($suites.Count))" -ForegroundColor Green
	exit 0
}

Write-Host "FAILED SUITES: $($failed -join ', ')" -ForegroundColor Red
exit 1
