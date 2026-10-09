#!/usr/bin/env bash
# THE way to rebuild the store environment. Runs all three steps in order from the repo root:
#   1. Blender: build_store.py  -> store_interior.glb, kit/*.glb, textures/*.png, store.blend, kit.blend
#   2. godot_setup.py           -> shared materials/*.tres + import settings (lossless, nearest, external materials)
#   3. Godot --import           -> reimport with those settings
# Skipping step 2 would let Godot re-extract per-GLB textures with default (VRAM-compressed) settings.
#
# Usage (from anywhere):
#   art_source/blender/environment/rebuild.sh [--no-kit | --kit-only]
#   BLENDER=/path/to/blender GODOT=/path/to/godot art_source/blender/environment/rebuild.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BLENDER="${BLENDER:-blender}"
GODOT="${GODOT:-${HOME}/tools/godot/godot}"

cd "${ROOT}"

echo "== 1/3 Blender: build store and kit (${BLENDER})"
# --python-exit-code makes Blender fail the script on a Python exception (it exits 0 otherwise).
"${BLENDER}" -b --factory-startup --python-exit-code 1 -P "${SCRIPT_DIR}/build_store.py" -- "$@"

echo "== 2/3 Godot materials and import settings"
python3 "${SCRIPT_DIR}/godot_setup.py"

echo "== 3/3 Godot reimport (${GODOT})"
"${GODOT}" --headless --path "${ROOT}" --import

echo "== done. Verify: ${GODOT} --headless --path . -s res://tests/run_tests.gd -- --filter=environment"
