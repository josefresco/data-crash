@echo off
rem Open Data Crash in the Godot editor (F5 to play).
cd /d "%~dp0"
start "" "Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" -e --path .
