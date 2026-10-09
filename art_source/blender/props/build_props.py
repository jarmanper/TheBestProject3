"""Builds every prop, tool pickup, viewmodel and HUD icon for Task 3 and exports them.

Run from anywhere (Blender 5.0, headless):
    blender -b --factory-startup -P art_source/blender/props/build_props.py
    blender -b --factory-startup -P art_source/blender/props/build_props.py -- --only locker,vm_mop
Options after "--":
    --only a,b,c   rebuild just these assets (props, viewmodels, or "icons"); skips the .blend save
    --no-icons     do not rewrite the icons
    --no-blend     do not save art_source/blender/props/props.blend

Outputs (paths relative to the repository root):
    assets/models/props/<name>.glb        (36 props and tool pickups)
    assets/models/viewmodels/vm_<id>.glb  (6 first-person viewmodels)
    assets/ui/icons/icon_<id>.png         (7 HUD icons, 32x32)
    art_source/blender/props/props.blend  (everything laid out in a lineup)
The script is deterministic: running it again reproduces the same files.
"""
import os
import sys

sys.dont_write_bytecode = True   # keep __pycache__ out of art_source/
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402

import icons  # noqa: E402
import props  # noqa: E402
import pxlib  # noqa: E402
import viewmodels  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PROPS_OUT = os.path.join(ROOT, "assets", "models", "props")
VM_OUT = os.path.join(ROOT, "assets", "models", "viewmodels")
ICON_OUT = os.path.join(ROOT, "assets", "ui", "icons")
BLEND_OUT = os.path.join(HERE, "props.blend")

VIEWMODEL_TRI_LIMIT = 800


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"only": None, "icons": True, "blend": True}
    i = 0
    while i < len(argv):
        if argv[i] == "--only":
            opts["only"] = set(argv[i + 1].split(","))
            i += 1
        elif argv[i] == "--no-icons":
            opts["icons"] = False
        elif argv[i] == "--no-blend":
            opts["blend"] = False
        i += 1
    return opts


def main():
    opts = parse_args()
    only = opts["only"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(PROPS_OUT, exist_ok=True)
    os.makedirs(VM_OUT, exist_ok=True)
    rows = []
    col_i = 0
    for name, (fn, kind) in props.BUILDERS.items():
        if only and name not in only:
            continue
        col = pxlib.new_collection(name)
        objs = fn(col, name)
        pxlib.export_glb(objs, os.path.join(PROPS_OUT, name + ".glb"))
        rows.append((name, kind, pxlib.triangle_count(objs)))
        for o in objs:   # lay the .blend out as a lineup: 6 per row, 2.5 m apart
            o.location.x += (col_i % 6) * 2.5
            o.location.y += (col_i // 6) * 2.5
        col_i += 1
    for name, fn in viewmodels.BUILDERS.items():
        if only and name not in only:
            continue
        col = pxlib.new_collection(name)
        objs = fn(col, name)
        pxlib.export_glb(objs, os.path.join(VM_OUT, name + ".glb"))
        tris = pxlib.triangle_count(objs)
        rows.append((name, "viewmodel", tris))
        if tris > VIEWMODEL_TRI_LIMIT:
            raise RuntimeError("%s has %d triangles (limit %d)" % (name, tris, VIEWMODEL_TRI_LIMIT))
        for o in objs:
            o.location.x += (col_i % 6) * 2.5
            o.location.y -= 4.0
        col_i += 1
    if opts["icons"] and (not only or "icons" in only):
        for path, opaque in icons.build_all(ICON_OUT):
            rows.append((os.path.basename(path), "icon", opaque))
    print("\nBUILD SUMMARY")
    for name, kind, value in rows:
        unit = "opaque px" if kind == "icon" else "tris"
        print("  %-26s %-10s %6d %s" % (name, kind, value, unit))
    if opts["blend"] and not only:
        bpy.context.preferences.filepaths.save_version = 0   # no props.blend1 backup
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=True)
        print("saved", BLEND_OUT)


main()
