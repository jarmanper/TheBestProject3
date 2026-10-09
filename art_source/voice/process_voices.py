"""Post-processes raw SAPI takes into radio / PA voice clips (Blender python: numpy + stdlib wave).

  blender -b --factory-startup --python-exit-code 1 -P process_voices.py -- lines.json raw_dir out_dir

Per line: trim silence (60 ms kept head/tail) -> shorten SAPI's long punctuation pauses ->
pitch/tempo resample (speaker + mimic settings from voices.py) to
8000 Hz -> channel colouring -> loudness normalise -> 16-bit mono WAV in out_dir, plus
out_dir/index.json ([{key, id, speaker, channel, mimic, text, seconds}]) for pack_voices.gd.

  walkie   : band-pass 300-3200 Hz, gentle tanh saturation, faint static bed + crackle, fades
  intercom : band-pass 250-3800 Hz, small-room reverb (synthetic IR), fades
Loudness: active-speech RMS -> -21 dBFS, soft-knee limit so peaks stay at or under -6 dBFS.
"""
import json
import os
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voices  # noqa: E402

OUT_RATE = 8000
TARGET_RMS_DB = -21.0
PEAK_CEIL = 10 ** (-6.0 / 20.0)


def read_wav(path):
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
        if w.getnchannels() > 1:
            data = data.reshape(-1, w.getnchannels()).mean(axis=1)
    return data, rate


def write_wav(path, data, rate):
    pcm = np.clip(np.round(data * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def band(data, rate, lo, hi, edge=1.35):
    """FFT band-pass with raised-cosine skirts (lo/edge..lo and hi..hi*edge)."""
    n = len(data)
    size = 1 << int(np.ceil(np.log2(max(n, 2))))
    spec = np.fft.rfft(data, size)
    freqs = np.fft.rfftfreq(size, 1.0 / rate)
    mask = np.ones_like(freqs)
    if lo > 0:
        lo0 = lo / edge
        mask[freqs <= lo0] = 0.0
        ramp = (freqs > lo0) & (freqs < lo)
        mask[ramp] = 0.5 - 0.5 * np.cos(np.pi * (freqs[ramp] - lo0) / (lo - lo0))
    hi1 = hi * edge
    mask[freqs >= hi1] = 0.0
    ramp = (freqs > hi) & (freqs < hi1)
    mask[ramp] = 0.5 + 0.5 * np.cos(np.pi * (freqs[ramp] - hi) / (hi1 - hi))
    return np.fft.irfft(spec * mask, size)[:n]


def trim(data, rate, floor_db=-42.0, pad=0.06):
    win = max(1, int(rate * 0.01))
    env = np.sqrt(np.convolve(data * data, np.ones(win) / win, mode="same"))
    peak = env.max() if len(env) else 0.0
    if peak <= 0:
        return data
    active = np.nonzero(env > peak * 10 ** (floor_db / 20.0))[0]
    start = max(0, active[0] - int(pad * rate))
    end = min(len(data), active[-1] + int(pad * rate))
    return data[start:end]


def tighten_pauses(data, rate, mimic):
    """Shortens SAPI's long punctuation pauses (comma ~0.3 s -> ~0.09 s, period ~0.7 s -> 0.16 s).
    In a mimic take the SSML marker break (the only pause >= MARKER_S) becomes the tell."""
    win = max(1, int(rate * 0.01))
    frames = len(data) // win
    if frames < 3:
        return data
    env = np.abs(data[: frames * win]).reshape(frames, win).max(axis=1)
    quiet = env <= env.max() * 10 ** (-40.0 / 20.0)
    pieces, last, i = [], 0, 0
    while i < frames:
        if not quiet[i]:
            i += 1
            continue
        j = i
        while j < frames and quiet[j]:
            j += 1
        gap = (j - i) * 0.01
        if i > 0 and j < frames and gap >= 0.1:
            if mimic and gap >= MARKER_S:
                keep = voices.MIMIC_PAUSE_MS / 1000.0
            else:
                keep = min(gap, 0.04 + 0.16 * gap, 0.16)
            half = int(keep * rate / 2)
            pieces.append(data[last: i * win + half])
            last = j * win - half
        i = j
    pieces.append(data[last:])
    return np.concatenate(pieces)


# SAPI shortens SSML breaks at faster rates (1.5 s -> ~1.05-1.2 s at +2/+3); natural pauses stay < 0.8 s.
MARKER_S = voices.MIMIC_BREAK_MS / 1000.0 * 0.6


def resample(data, rate, factor, out_rate):
    """Plays `data` `factor` times faster (pitch and tempo) and converts to out_rate."""
    data = band(data, rate, 0, min(out_rate * 0.45, rate * 0.45) / max(factor, 1.0), edge=1.1)
    duration = len(data) / rate / factor
    count = int(duration * out_rate)
    src = np.arange(count) * (rate * factor / out_rate)
    return np.interp(src, np.arange(len(data)), data)


def fades(data, rate, fade_in=0.012, fade_out=0.03):
    a = min(len(data), int(rate * fade_in))
    b = min(len(data), int(rate * fade_out))
    if a:
        data[:a] *= np.linspace(0.0, 1.0, a)
    if b:
        data[-b:] *= np.linspace(1.0, 0.0, b)
    return data


def active_rms(data, rate):
    win = max(1, int(rate * 0.02))
    frames = len(data) // win
    if frames == 0:
        return float(np.sqrt(np.mean(data * data)) + 1e-9)
    rms = np.sqrt((data[: frames * win].reshape(frames, win) ** 2).mean(axis=1))
    gate = rms.max() * 10 ** (-30.0 / 20.0)
    loud = rms[rms > gate]
    return float(np.sqrt(np.mean(loud * loud)) + 1e-9)


def loudness(data, rate):
    data = data * (10 ** (TARGET_RMS_DB / 20.0) / active_rms(data, rate))
    knee = PEAK_CEIL * 0.8
    over = np.abs(data) > knee
    span = PEAK_CEIL - knee
    data[over] = np.sign(data[over]) * (knee + span * np.tanh((np.abs(data[over]) - knee) / span))
    return data


def walkie(data, rate, rng):
    data = band(data, rate, 300, 3200)
    data = data / (np.abs(data).max() + 1e-9)
    drive = 2.2
    data = np.tanh(drive * data) / np.tanh(drive)
    data = band(data, rate, 300, 3200)
    data = data / (np.abs(data).max() + 1e-9)
    noise = band(rng.standard_normal(len(data)), rate, 400, 3600)
    noise *= 10 ** (-36.0 / 20.0) / (np.sqrt(np.mean(noise * noise)) + 1e-9)
    crackle = np.zeros(len(data))
    for _ in range(rng.integers(2, 6)):
        at = rng.integers(0, max(1, len(data) - 40))
        crackle[at:at + 30] += rng.standard_normal(min(30, len(data) - at)) * 0.05
    return fades(data * 0.7 + noise + crackle, rate)


_IR_CACHE = {}


def room_ir(rate):
    if rate not in _IR_CACHE:
        rng = np.random.default_rng(7)
        length = int(rate * 0.45)
        t = np.arange(length) / rate
        ir = rng.standard_normal(length) * np.exp(-t / 0.075)  # ~0.5 s RT60
        ir[: int(rate * 0.008)] = 0.0
        for ms, gain in ((11, 0.55), (19, 0.4), (29, 0.32), (43, 0.22)):
            ir[int(rate * ms / 1000.0)] += gain * 6
        ir = band(ir, rate, 300, 3400)
        _IR_CACHE[rate] = ir / np.sqrt(np.sum(ir * ir))
    return _IR_CACHE[rate]


def intercom(data, rate):
    data = band(data, rate, 250, 3800)
    data = data / (np.abs(data).max() + 1e-9)
    data = np.concatenate([data, np.zeros(int(rate * 0.22))])  # room for the reverb tail
    ir = room_ir(rate)
    size = 1 << int(np.ceil(np.log2(len(data) + len(ir))))
    wet = np.fft.irfft(np.fft.rfft(data, size) * np.fft.rfft(ir, size), size)[: len(data)]
    wet *= np.sqrt(np.mean(data * data)) / (np.sqrt(np.mean(wet * wet)) + 1e-9)
    mixed = data + 0.32 * wet
    mixed = 0.85 * np.tanh(1.2 * mixed / (np.abs(mixed).max() + 1e-9))
    return fades(mixed, rate, 0.01, 0.12)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    lines_json, raw_dir, out_dir = args[:3]
    os.makedirs(out_dir, exist_ok=True)
    lines = json.load(open(lines_json, encoding="utf-8"))
    index = []
    missing = 0
    for line in lines:
        cid = voices.clip_id(line)
        raw_path = os.path.join(raw_dir, cid + ".wav")
        if not os.path.exists(raw_path):
            missing += 1
            continue
        data, rate = read_wav(raw_path)
        data = trim(data, rate)
        data = tighten_pauses(data, rate, line["mimic"])
        data = resample(data, rate, voices.resample_factor(line), OUT_RATE)
        rng = np.random.default_rng(int(cid[-8:], 16))
        if line["channel"] == "intercom":
            data = intercom(data, OUT_RATE)
        else:
            data = walkie(data, OUT_RATE, rng)
        data = loudness(data, OUT_RATE)
        write_wav(os.path.join(out_dir, cid + ".wav"), data, OUT_RATE)
        index.append({"key": voices.clip_key(line), "id": cid, "speaker": line["speaker"],
                      "channel": line["channel"], "mimic": line["mimic"], "text": line["text"],
                      "seconds": round(len(data) / OUT_RATE, 3)})
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as out:
        json.dump(index, out, indent=1)
    print("processed %d clips (%d raw takes missing)" % (len(index), missing))
    if missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
