"""Sanity-check analyzer for the generated audio (Task 4).

Since the files can't be listened to, this computes objective metrics for
every WAV under assets/audio/** and prints a markdown table: duration,
peak dBFS, RMS dBFS, DC offset, clipped-sample count, loop-seam
discontinuity (for files in LOOP_IDS), and spectral centroid (Hz).

Run with Blender's bundled Python (numpy):

    blender -b --factory-startup -P art_source/audio/analyze_audio.py

Also renders spectrogram PNGs for a handful of key sounds into a scratch
directory (not committed) so they can be inspected with an image-reading
tool, per common.md guidance for debug images.
"""

import math
import os
import struct
import wave
import zlib

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")

# Ids (basenames without extension) that are meant to loop (from autoload/sfx.gd LOOPING,
# translated to filenames).
LOOP_BASENAMES = {
    "heartbeat_loop", "task_progress_loop", "monster_breath_loop",
    "amb_store_hum", "amb_fluorescent_buzz", "amb_freezer_hum", "amb_backroom",
    "music_dread_loop", "music_chase_loop",
}

SPECTROGRAM_TARGETS = [
    "sfx/monster_scream.wav",
    "sfx/monster_reveal.wav",
    "sfx/walkie_voice_01.wav",
    "sfx/walkie_voice_mimic_01.wav",
    "sfx/intercom_voice_01.wav",
    "ambience/amb_fluorescent_buzz.wav",
    "ambience/amb_store_hum.wav",
    "music/music_dread_loop.wav",
    "music/music_chase_loop.wav",
    "sfx/footstep_tile_01.wav",
]

OUT_DIR = os.environ.get("AUDIO_ANALYSIS_OUT", "/tmp/audio_analysis")


def read_wav(path):
    with wave.open(path, "rb") as f:
        sr = f.getframerate()
        n = f.getnframes()
        sw = f.getsampwidth()
        raw = f.readframes(n)
    if sw == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    else:
        raise ValueError(f"unexpected sample width {sw} in {path}")
    return data, sr


def spectral_centroid(x, sr):
    n = len(x)
    if n < 2:
        return 0.0
    window = np.hanning(n)
    X = np.abs(np.fft.rfft(x * window))
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    total = np.sum(X) + 1e-12
    return float(np.sum(X * freqs) / total)


def analyze_file(path):
    x, sr = read_wav(path)
    n = len(x)
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x ** 2)))
    dc = float(np.mean(x))
    clipped = int(np.sum(np.abs(x) >= 0.999))
    basename = os.path.splitext(os.path.basename(path))[0]
    is_loop = basename in LOOP_BASENAMES
    seam_delta = None
    seam_slope_delta = None
    if is_loop and n > 4:
        seam_delta = float(abs(x[0] - x[-1]))
        slope_start = x[1] - x[0]
        slope_end = x[-1] - x[-2]
        seam_slope_delta = float(abs(slope_start - slope_end))
    centroid = spectral_centroid(x, sr)
    return {
        "path": path,
        "duration": n / sr,
        "sr": sr,
        "peak_dbfs": 20 * math.log10(max(peak, 1e-12)),
        "rms_dbfs": 20 * math.log10(max(rms, 1e-12)),
        "dc_offset": dc,
        "clipped_samples": clipped,
        "is_loop": is_loop,
        "seam_delta": seam_delta,
        "seam_slope_delta": seam_slope_delta,
        "centroid_hz": centroid,
    }


# --- minimal PNG writer (no PIL/scipy available) ----------------------------

def write_png_gray(path, array_u8):
    """array_u8: 2D uint8 array, [0]=rows (top to bottom), [1]=cols."""
    height, width = array_u8.shape

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    raw = bytearray()
    for row in range(height):
        raw.append(0)  # no filter
        raw.extend(array_u8[row].tobytes())
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", idat))
        f.write(chunk(b"IEND", b""))


def render_spectrogram(path, out_png, fft_size=1024, hop=256, max_width=900, max_height=300):
    x, sr = read_wav(path)
    n = len(x)
    if n < fft_size:
        x = np.pad(x, (0, fft_size - n))
        n = len(x)
    window = np.hanning(fft_size)
    n_frames = max(1, (n - fft_size) // hop + 1)
    spec = np.zeros((fft_size // 2 + 1, n_frames))
    for i in range(n_frames):
        seg = x[i * hop: i * hop + fft_size]
        spec[:, i] = np.abs(np.fft.rfft(seg * window))
    spec_db = 20 * np.log10(spec + 1e-6)
    spec_db = np.clip(spec_db, -80, None)
    spec_db -= spec_db.max()  # 0 dB at peak, negative below

    # Downsample / upsample to a manageable image size.
    freq_bins = spec_db.shape[0]
    img = spec_db
    # Flip so low freq at bottom.
    img = img[::-1, :]
    # Normalize to 0..255 (0 dB -> 255, -80 dB -> 0).
    norm = np.clip((img + 80) / 80.0, 0, 1)
    img_u8 = (norm * 255).astype(np.uint8)

    # Resize (nearest) to cap dimensions.
    h, w = img_u8.shape
    scale_h = min(1.0, max_height / h)
    scale_w = min(1.0, max_width / w)
    new_h = max(1, int(h * scale_h))
    new_w = max(1, int(w * scale_w))
    row_idx = (np.arange(new_h) / new_h * h).astype(int)
    col_idx = (np.arange(new_w) / new_w * w).astype(int)
    small = img_u8[row_idx][:, col_idx]

    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    write_png_gray(out_png, small)
    return out_png


def main():
    rows = []
    for sub in ("sfx", "ambience", "music"):
        d = os.path.join(AUDIO_DIR, sub)
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if fname.endswith(".wav"):
                rows.append(analyze_file(os.path.join(d, fname)))

    print(f"{'file':34s} {'dur':>6s} {'peak dBFS':>10s} {'rms dBFS':>9s} {'dc':>10s} "
          f"{'clip':>5s} {'centroid Hz':>12s} {'seam dv':>9s} {'seam dslope':>12s}")
    issues = []
    for r in rows:
        name = os.path.relpath(r["path"], AUDIO_DIR)
        seam = f"{r['seam_delta']:.2e}" if r["seam_delta"] is not None else "-"
        seam_slope = f"{r['seam_slope_delta']:.2e}" if r["seam_slope_delta"] is not None else "-"
        print(f"{name:34s} {r['duration']:6.2f} {r['peak_dbfs']:10.2f} {r['rms_dbfs']:9.2f} "
              f"{r['dc_offset']:10.2e} {r['clipped_samples']:5d} {r['centroid_hz']:12.1f} "
              f"{seam:>9s} {seam_slope:>12s}")
        if r["clipped_samples"] > 0:
            issues.append(f"{name}: {r['clipped_samples']} clipped samples")
        if abs(r["dc_offset"]) > 0.01:
            issues.append(f"{name}: DC offset {r['dc_offset']:.4f}")
        if r["peak_dbfs"] > -0.5:
            issues.append(f"{name}: peak {r['peak_dbfs']:.2f} dBFS too hot")
        if r["is_loop"] and r["duration"] < 4.0:
            issues.append(f"{name}: loop shorter than 4s ({r['duration']:.2f}s)")
        if not r["is_loop"] and r["duration"] >= 8.0:
            issues.append(f"{name}: one-shot >= 8s ({r['duration']:.2f}s)")
        if r["seam_delta"] is not None and r["seam_delta"] > 0.02:
            issues.append(f"{name}: loop seam discontinuity {r['seam_delta']:.4f}")

    print(f"\n{len(rows)} files analyzed.")
    if issues:
        print("\nISSUES:")
        for i in issues:
            print(" -", i)
    else:
        print("No issues found (clipping / DC offset / loop seam / duration).")

    print(f"\nRendering {len(SPECTROGRAM_TARGETS)} spectrograms to {OUT_DIR} ...")
    for rel in SPECTROGRAM_TARGETS:
        src = os.path.join(AUDIO_DIR, rel)
        if not os.path.exists(src):
            print("  MISSING", src)
            continue
        out_png = os.path.join(OUT_DIR, rel.replace("/", "_").replace(".wav", ".png"))
        render_spectrogram(src, out_png)
        print("  wrote", out_png)


if __name__ == "__main__":
    main()
