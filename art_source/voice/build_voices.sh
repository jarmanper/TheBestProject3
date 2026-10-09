#!/usr/bin/env bash
# Regenerates every spoken walkie / intercom line (assets/audio/voice/**). Re-run after
# editing ManagerLines, StationLayout manager_lines, CoworkerLines, MonsterLines,
# Catalog.ZONES or Catalog.COWORKERS -- tests/audio/test_voice_lines.gd fails until you do.
#
#   bash art_source/voice/build_voices.sh            (from the repo root, in WSL)
#
# Steps:
#   1. dump_lines.gd     Godot enumerates every final string (VoiceLines.enumerate_all) -> lines.json
#   2. voices.py         per-speaker SAPI voice/rate + SSML (mimic pause) -> jobs.tsv
#   3. synth.ps1         Windows SAPI (David / Zira) speaks each job -> raw 16 kHz WAVs
#   4. process_voices.py Blender python + numpy: trim, tighten pauses, pitch/tempo resample, walkie or PA
#                        colouring, loudness -> 8000 Hz 16-bit WAVs + index.json
#   5. pack_voices.gd    Godot packs them as QOA AudioStreamWAV .res + voice_manifest.gd
# Speaker settings (voice, rate, resample, mimic tell) live in voices.py.
#
# Needs: ~/tools/godot/godot, blender, powershell.exe (Windows SAPI), python3.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-$HOME/tools/godot/godot}"
WIN_TEMP_WSL="${WIN_TEMP_WSL:-/mnt/c/Users/jlion/AppData/Local/Temp}"
WORK="$WIN_TEMP_WSL/gs_voice"
WIN_WORK="$(wslpath -w "$WORK" 2>/dev/null || echo 'C:\Users\jlion\AppData\Local\Temp\gs_voice')"
STAGE="${STAGE:-$(mktemp -d)}"

mkdir -p "$WORK/raw"
rm -f "$WORK"/raw/*.wav
"$GODOT" --headless --path . -s res://art_source/voice/dump_lines.gd -- "$STAGE/lines.json"
python3 art_source/voice/voices.py "$STAGE/lines.json" "$WORK/jobs.tsv" "$WIN_WORK\\raw"
cp art_source/voice/synth.ps1 "$WORK/synth.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_WORK\\synth.ps1" "$WIN_WORK\\jobs.tsv"
blender -b --factory-startup --python-exit-code 1 -P art_source/voice/process_voices.py -- \
	"$STAGE/lines.json" "$WORK/raw" "$STAGE/wav"
"$GODOT" --headless --path . -s res://art_source/voice/pack_voices.gd -- "$STAGE/wav"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "voice clips: $(find assets/audio/voice -name '*.res' | wc -l), $(du -sh assets/audio/voice | cut -f1)"
