"""Named materials shared by all props. `get(name)` creates each material once.

Textured materials sample their image with Closest (exported as glTF NEAREST); a few
untextured accent materials use a flat colour. Material names show up in Godot as the
StandardMaterial3D resource names.
"""
import textures
from pxlib import material

SPECS = {
    # metals
    "MetalOlive": dict(tex="metal_olive", rough=0.7, metal=0.2),
    "MetalGrey": dict(tex="metal_grey", rough=0.65, metal=0.25),
    "MetalDark": dict(tex="metal_dark", rough=0.6, metal=0.25),
    "MetalSafe": dict(tex="metal_safe", rough=0.55, metal=0.3),
    "MetalLight": dict(tex="metal_light", rough=0.45, metal=0.45),
    "Steel": dict(tex="steel", rough=0.4, metal=0.45),
    "Brass": dict(tex="brass", rough=0.4, metal=0.55),
    # plastics / rubber
    "PlasticBlack": dict(tex="plastic_black", rough=0.5),
    "PlasticOlive": dict(tex="plastic_olive", rough=0.7),
    "PlasticYellow": dict(tex="plastic_yellow", rough=0.55),
    "PlasticBeige": dict(tex="plastic_beige", rough=0.7),
    "OrangePlastic": dict(tex="orange_plastic", rough=0.5),
    "ChairShell": dict(tex="chair_shell", rough=0.6),
    "CounterTray": dict(tex="counter_tray", rough=0.6),
    "Rubber": dict(tex="rubber", rough=0.9),
    "RedPlastic": dict(color="B93B32", rough=0.45),
    "GreenLight": dict(color="3E8A4A", emit="7BE08A", emit_strength=1.0, rough=0.3),
    # cardboard / paper / wood
    "Cardboard": dict(tex="cardboard", rough=0.95),
    "BoxAtlas": dict(tex="box_atlas", rough=0.95),
    "StockBox": dict(tex="stock_box", rough=0.95),
    "Wood": dict(tex="wood", rough=0.9),
    "Hardboard": dict(tex="hardboard", rough=0.8),
    "Newsprint": dict(tex="newsprint", rough=0.95, double=True),
    "PaperLog": dict(tex="paper_log", rough=0.9),
    "TimeCard": dict(tex="time_card", rough=0.9),
    "Products": dict(tex="products", rough=0.6),
    "MopStrands": dict(tex="mop_strands", rough=0.95),
    # fabric / gloves
    "OrangeFabric": dict(tex="orange_fabric", rough=0.95),
    "Glove": dict(tex="glove", rough=0.85),
    "FabricDark": dict(tex="fabric_dark", rough=0.95),
    "BagBlack": dict(tex="bag_black", rough=0.35),
    # surfaces
    "Laminate": dict(tex="laminate", rough=0.5),
    "LaminateDark": dict(tex="laminate_dark", rough=0.5),
    "Water": dict(tex="water", rough=0.08),
    "SinkInside": dict(tex="sink_inside", rough=0.4, metal=0.3),
    # signs / labels / panels
    "WetSign": dict(tex="wet_sign", rough=0.5),
    "Labels": dict(tex="labels", rough=0.6),
    "Hazard": dict(tex="hazard", rough=0.6),
    "BalerChamber": dict(tex="baler_chamber", rough=0.8),
    "ControlBox": dict(tex="control_box", rough=0.6),
    "ClockFace": dict(tex="clock_face", rough=0.4),
    "TimeClockBody": dict(tex="time_clock_body", rough=0.6),
    "KeyBoard": dict(tex="key_board", rough=0.8),
    "PegBoard": dict(tex="peg_board", rough=0.7),
    "LabelRoll": dict(tex="label_roll", rough=0.8),
    "CutterBody": dict(tex="cutter_body", rough=0.5),
    "Walkie": dict(tex="walkie", rough=0.5),
    "Drawers": dict(tex="drawers", rough=0.6, metal=0.25),
    "SafeFront": dict(tex="safe_front", rough=0.55, metal=0.3),
    "BreakerInside": dict(tex="breaker_inside", rough=0.6),
    "BreakerDoor": dict(tex="breaker_door", rough=0.6, metal=0.2),
    "VendingKeypad": dict(tex="vending_keypad", rough=0.5),
    "FlashlightBody": dict(tex="flashlight_body", rough=0.45, metal=0.2),
    "Lens": dict(tex="lens", rough=0.2, emit=True, emit_strength=0.6),
    # emissive / transparent
    "VendingPanel": dict(tex="vending_panel", rough=0.2, emit=True, emit_strength=1.2),
    "CRTScreen": dict(tex="crt_screen", rough=0.2, emit=True, emit_strength=1.3),
    "Sparks": dict(color="FFE9A0", emit="FFE2A0", emit_strength=6.0, double=True),
    "SparksHot": dict(color="E87932", emit="F09A40", emit_strength=4.0, double=True),
    "Spill": dict(tex="spill", rough=0.06, alpha="BLEND"),
    "Scorch": dict(tex="scorch", rough=1.0, alpha="BLEND"),
    "WireGrid": dict(tex="wire_grid", rough=0.5, metal=0.3, alpha="CLIP", double=True),
    "LockerDoor": dict(tex="locker_door", rough=0.7, metal=0.2, alpha="CLIP"),
}


def get(name):
    spec = dict(SPECS[name])
    tex = spec.pop("tex", None)
    image = textures.get(tex) if tex else None
    return material(name, image=image, **spec)
