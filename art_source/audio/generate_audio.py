"""Procedural audio generator for Graveyard Shift (Task 4: all game audio).

Regenerates every sound base path listed in `autoload/sfx.gd`'s SOUNDS dict, as
mono 16-bit PCM WAV files under assets/audio/{sfx,ambience,music}/. Everything
is synthesized with numpy (no recordings, no external assets, no scipy) -- see
assets/audio/CREDITS.md.

Run with Blender's bundled Python (has numpy; stdlib `wave` writes the files):

    blender -b --factory-startup -P art_source/audio/generate_audio.py

Deterministic: every file's RNG is seeded from its own relative path (via
zlib.crc32), so re-running this script regenerates byte-identical output.

Web build note (docs/ARCHITECTURE.md): the web export plays audio as Web Audio
samples, which ignores Godot audio bus effects. So the walkie radio band-pass
and PA reverb are baked directly into the generated samples below, not applied
by a bus effect.
"""

import math
import os
import wave
import zlib

import numpy as np

# ---------------------------------------------------------------------------
# Paths / constants
# ---------------------------------------------------------------------------

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
AMB_DIR = os.path.join(ROOT, "assets", "audio", "ambience")
MUS_DIR = os.path.join(ROOT, "assets", "audio", "music")

SR_SFX = 44100   # footsteps / UI / voice / monster / most one-shots
SR_LOOP = 22050  # ambience + music loops (brief: 22.05 kHz OK for these)

for _d in (SFX_DIR, AMB_DIR, MUS_DIR):
    os.makedirs(_d, exist_ok=True)


def seeded_rng(key: str) -> np.random.Generator:
    """Deterministic RNG from a stable (non-randomized) hash of `key`."""
    seed = zlib.crc32(key.encode("utf-8"))
    return np.random.default_rng(seed)


# ---------------------------------------------------------------------------
# Low-level DSP helpers (no scipy available)
# ---------------------------------------------------------------------------

def db_to_amp(db: float) -> float:
    return 10.0 ** (db / 20.0)


def amp_to_db(amp: float) -> float:
    return 20.0 * math.log10(max(amp, 1e-12))


def _next_pow2(n: int) -> int:
    p = 1
    while p < n:
        p <<= 1
    return p


def fft_convolve(x: np.ndarray, h: np.ndarray) -> np.ndarray:
    """Full linear convolution, length len(x)+len(h)-1."""
    n = len(x) + len(h) - 1
    nfft = _next_pow2(n)
    X = np.fft.rfft(x, nfft)
    H = np.fft.rfft(h, nfft)
    y = np.fft.irfft(X * H, nfft)
    return y[:n]


def apply_ir_same(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Convolve and crop back to len(x) (causal, front-aligned)."""
    return fft_convolve(x, ir)[: len(x)]


def fft_lowpass(x: np.ndarray, sr: int, cutoff: float, trans: float = None) -> np.ndarray:
    trans = trans or max(20.0, cutoff * 0.25)
    n = len(x)
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    mask = np.clip((cutoff + trans - freqs) / trans, 0.0, 1.0)
    return np.fft.irfft(X * mask, n)


def fft_highpass(x: np.ndarray, sr: int, cutoff: float, trans: float = None) -> np.ndarray:
    trans = trans or max(20.0, cutoff * 0.25)
    n = len(x)
    X = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    mask = np.clip((freqs - (cutoff - trans)) / trans, 0.0, 1.0)
    return np.fft.irfft(X * mask, n)


def fft_bandpass(x: np.ndarray, sr: int, low: float, high: float) -> np.ndarray:
    return fft_lowpass(fft_highpass(x, sr, low), sr, high)


def resonator_ir(freq: float, bw_hz: float, sr: int, dur: float = 0.05) -> np.ndarray:
    """Impulse response of a simple 2-pole resonant (formant-like) filter."""
    n = max(8, int(sr * dur))
    r = math.exp(-math.pi * bw_hz / sr)
    theta = 2.0 * math.pi * freq / sr
    coef_a = 2.0 * r * math.cos(theta)
    coef_b = -(r * r)
    y = np.zeros(n)
    y_prev1 = 0.0
    y_prev2 = 0.0
    for i in range(n):
        x = 1.0 if i == 0 else 0.0
        yi = x + coef_a * y_prev1 + coef_b * y_prev2
        y[i] = yi
        y_prev2 = y_prev1
        y_prev1 = yi
    peak = np.max(np.abs(y)) + 1e-12
    return y / peak


def formant_filter(x: np.ndarray, sr: int, freq: float, bw: float, dur: float = 0.05) -> np.ndarray:
    return apply_ir_same(x, resonator_ir(freq, bw, sr, dur))


def reverb_ir(sr: int, decay: float, dur: float, rng: np.random.Generator) -> np.ndarray:
    n = max(8, int(sr * dur))
    noise = rng.standard_normal(n)
    env = np.exp(-np.arange(n) / (sr * decay / 5.0))
    ir = noise * env
    ir[0] += 1.0
    return ir / (np.max(np.abs(ir)) + 1e-9)


def apply_reverb(x: np.ndarray, sr: int, decay: float, dur: float, mix: float,
                  rng: np.random.Generator) -> np.ndarray:
    ir = reverb_ir(sr, decay, dur, rng)
    wet = fft_convolve(x, ir)
    dry = np.pad(x, (0, len(wet) - len(x)))
    return dry + mix * wet


def declick_edges(x: np.ndarray, ramp_samples: int) -> np.ndarray:
    n = len(x)
    ramp_samples = max(1, min(ramp_samples, n // 2))
    env = np.ones(n)
    ramp = np.linspace(0.0, 1.0, ramp_samples, endpoint=False)
    env[:ramp_samples] *= ramp
    env[-ramp_samples:] *= ramp[::-1]
    return x * env


def normalize_peak(x: np.ndarray, target_db: float) -> np.ndarray:
    peak = np.max(np.abs(x)) + 1e-12
    return x * (db_to_amp(target_db) / peak)


def finalize(x: np.ndarray, sr: int, target_db: float, declick_ms: float = 3.0) -> np.ndarray:
    x = x - np.mean(x)
    x = declick_edges(x, max(1, int(sr * declick_ms / 1000.0)))
    x = normalize_peak(x, target_db)
    return np.clip(x, -0.999, 0.999)


def make_loop(loop_fn, target_duration: float, sr: int, rng: np.random.Generator,
              fade_ratio: float = 0.08, min_fade: float = 0.15, max_fade: float = 1.5) -> np.ndarray:
    """Crossfade-wrap `loop_fn(n_samples, sr, rng)` into a seamless loop of
    ~target_duration seconds. See module docstring for the technique: the
    overflow past the loop point is blended back into the start so the sample
    at the wrap boundary is the literal continuation of the sample before it.
    """
    fade_dur = min(max(target_duration * fade_ratio, min_fade), max_fade)
    n_fade = int(fade_dur * sr)
    n_target = int(target_duration * sr)
    raw = loop_fn(n_target + n_fade, sr, rng)
    n_fade = min(n_fade, len(raw) - n_target) if len(raw) > n_target else n_fade
    out = raw[:n_target].copy()
    t = np.linspace(0.0, 1.0, n_fade, endpoint=False)
    fade_in = np.sin(t * math.pi / 2.0) ** 2
    fade_out = np.cos(t * math.pi / 2.0) ** 2
    out[:n_fade] = raw[:n_fade] * fade_in + raw[n_target:n_target + n_fade] * fade_out
    return out


def write_wav(path: str, samples: np.ndarray, sr: int) -> None:
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------
# Reusable sound "flavors"
# ---------------------------------------------------------------------------

def noise_burst(duration: float, sr: int, rng: np.random.Generator, band=(100, 6000),
                 decay: float = 0.05) -> np.ndarray:
    n = max(8, int(duration * sr))
    noise = rng.standard_normal(n)
    filt = fft_bandpass(noise, sr, band[0], band[1])
    t = np.arange(n) / sr
    env = np.exp(-t / decay)
    return filt * env


def click(duration: float, sr: int, rng: np.random.Generator, band=(800, 8000)) -> np.ndarray:
    n = max(8, int(duration * sr))
    noise = rng.standard_normal(n)
    filt = fft_bandpass(noise, sr, band[0], band[1])
    env = np.exp(-np.arange(n) / sr / 0.01)
    return filt * env


def thump(freq: float, duration: float, sr: int, decay: float = 0.15) -> np.ndarray:
    n = max(8, int(duration * sr))
    t = np.arange(n) / sr
    inst_freq = freq * np.exp(-t * 2.0)
    phase = np.cumsum(2 * math.pi * inst_freq / sr)
    sig = np.sin(phase)
    env = np.exp(-t / decay)
    return sig * env


def tone_ping(freq: float, duration: float, sr: int, decay: float = 0.1,
              harmonics=(1, 2, 3), amp_ratios=(1.0, 0.4, 0.15)) -> np.ndarray:
    n = max(8, int(duration * sr))
    t = np.arange(n) / sr
    sig = np.zeros(n)
    for h, a in zip(harmonics, amp_ratios):
        sig += a * np.sin(2 * math.pi * freq * h * t)
    env = np.exp(-t / decay)
    return sig * env


def two_tone_chime(f1: float, f2: float, sr: int, dur_each: float = 0.3,
                    gap: float = 0.05, decay: float = 0.4) -> np.ndarray:
    tone1 = tone_ping(f1, dur_each, sr, decay=decay)
    tone2 = tone_ping(f2, dur_each, sr, decay=decay)
    gap_samples = int(gap * sr)
    return np.concatenate([tone1, np.zeros(gap_samples), tone2])


def impact_hit(sr: int, rng: np.random.Generator, dur: float = 0.25, band=(100, 6000)) -> np.ndarray:
    burst = noise_burst(dur, sr, rng, band=band, decay=max(0.02, dur * 0.18))
    low = thump(70.0, dur, sr, decay=max(0.03, dur * 0.25))
    n = max(len(burst), len(low))
    out = np.zeros(n)
    out[: len(burst)] += burst
    out[: len(low)] += low * 0.8
    return out


def crack_hit(sr: int, rng: np.random.Generator, dur: float = 0.07, band=(300, 9000)) -> np.ndarray:
    return noise_burst(dur, sr, rng, band=band, decay=0.015)


def dissonant_cluster(duration: float, sr: int, rng: np.random.Generator,
                       base_freq: float = 110.0) -> np.ndarray:
    n = max(8, int(duration * sr))
    t = np.arange(n) / sr
    ratios = [1.0, 1.06, 1.414, 1.9, 2.53]
    sig = np.zeros(n)
    for r in ratios:
        sig += np.sin(2 * math.pi * base_freq * r * t) / len(ratios)
    env = np.exp(-t / (duration * 0.4))
    sig *= env
    sig += 0.15 * rng.standard_normal(n) * np.exp(-t / 0.05)
    return apply_reverb(sig, sr, decay=0.5, dur=0.4, mix=0.3, rng=rng)


def descending_buzz(sr: int, rng: np.random.Generator, f_start=300.0, f_end=90.0,
                     dur: float = 0.4) -> np.ndarray:
    n = max(8, int(dur * sr))
    t = np.arange(n) / sr
    freq = f_start + (f_end - f_start) * (t / dur)
    phase = np.cumsum(2 * math.pi * freq / sr)
    sig = np.sign(np.sin(phase)) * 0.6 + np.sin(phase) * 0.4
    env = np.exp(-t / (dur * 0.75))
    return sig * env


def metal_creak_gen(sr: int, rng: np.random.Generator, dur: float = 1.4) -> np.ndarray:
    n = int(dur * sr)
    t = np.arange(n) / sr
    noise = rng.standard_normal(n)
    chunk = int(sr * 0.1)
    step = chunk // 2
    out = np.zeros(n + chunk)
    wsum = np.zeros(n + chunk)
    win = np.hanning(chunk)
    f1, f2 = rng.uniform(300, 600), rng.uniform(900, 1600)
    pos = 0
    while pos < n:
        frac = pos / max(1, n)
        freq = f1 + (f2 - f1) * frac + rng.uniform(-30, 30)
        seg = noise[pos:pos + chunk]
        if len(seg) < chunk:
            seg = np.pad(seg, (0, chunk - len(seg)))
        filt = formant_filter(seg, sr, freq, 60, dur=0.04)
        out[pos:pos + chunk] += filt[:chunk] * win
        wsum[pos:pos + chunk] += win
        pos += step
    wsum[wsum < 1e-6] = 1.0
    sig = (out / wsum)[:n]
    env = np.clip(np.sin(math.pi * np.clip(t / dur, 0, 1)), 0, 1) ** 0.5
    return sig * env


def box_rustle_gen(sr: int, rng: np.random.Generator, dur: float = 0.6) -> np.ndarray:
    n = int(dur * sr)
    noise = rng.standard_normal(n)
    filt = fft_bandpass(noise, sr, 1000, 7000)
    window = max(4, int(sr * 0.005))
    kernel = np.ones(window) / window
    mod = np.convolve(np.abs(rng.standard_normal(n)), kernel, mode="same")
    mod /= (np.max(mod) + 1e-9)
    env = np.exp(-np.arange(n) / sr / 0.4)
    return filt * mod * env


def cart_rattle_gen(sr: int, rng: np.random.Generator, dur: float = 0.9) -> np.ndarray:
    n = int(dur * sr)
    sig = np.zeros(n)
    n_clinks = rng.integers(6, 10)
    for _ in range(n_clinks):
        pos = rng.integers(0, max(1, n - 2000))
        cl = click(0.04, sr, rng, band=(2000, 8000))
        end = min(n, pos + len(cl))
        sig[pos:end] += cl[: end - pos] * rng.uniform(0.4, 0.9)
    low = thump(70, dur, sr, decay=0.3)
    sig[: len(low)] += low * 0.3
    return sig


def light_flicker_gen(sr: int, rng: np.random.Generator, dur: float = 0.4) -> np.ndarray:
    n = int(dur * sr)
    t = np.arange(n) / sr
    buzz = 0.5 * np.sin(2 * math.pi * 120 * t) + 0.2 * np.sin(2 * math.pi * 240 * t)
    crackle = np.zeros(n)
    for _ in range(int(rng.integers(3, 8))):
        pos = rng.integers(0, max(1, n - 200))
        length = int(rng.integers(20, 150))
        burst = rng.standard_normal(length) * np.exp(-np.arange(length) / 20.0)
        end = min(n, pos + length)
        crackle[pos:end] += burst[: end - pos]
    steps = int(rng.integers(3, 6))
    bounds = np.sort(rng.integers(0, n, steps))
    flick_env = np.ones(n)
    prev = 0
    for b in bounds:
        flick_env[prev:b] = rng.uniform(0.2, 1.0)
        prev = b
    flick_env[prev:] = rng.uniform(0.2, 1.0)
    return buzz * flick_env * 0.5 + crackle * 0.6


def distant_bang_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    hit = impact_hit(sr, rng, dur=0.3, band=(60, 3000))
    hit = fft_lowpass(hit, sr, 2500)
    return apply_reverb(hit, sr, decay=0.8, dur=0.6, mix=0.5, rng=rng)


# --- footsteps --------------------------------------------------------------

def footstep_tile_gen(sr: int, rng: np.random.Generator, heavy: bool = False) -> np.ndarray:
    dur = 0.22
    n = int(dur * sr)
    tap = click(0.03, sr, rng, band=(1500, 7000))
    body = thump(90 + rng.uniform(-10, 10), 0.15, sr, decay=0.05)
    wet = noise_burst(0.12, sr, rng, band=(2000, 9000), decay=0.03)
    out = np.zeros(n)
    out[: len(tap)] += tap * 0.6
    out[: len(body)] += body * (0.8 if heavy else 0.5)
    start_wet = int(0.01 * sr)
    out[start_wet:start_wet + len(wet)] += wet * 0.5
    return out


def footstep_monster_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    base = footstep_tile_gen(sr, rng, heavy=True)
    claw = noise_burst(0.05, sr, rng, band=(3000, 9000), decay=0.02)
    n = max(len(base), int(0.02 * sr) + len(claw))
    out = np.zeros(n)
    out[: len(base)] += base
    start = int(0.02 * sr)
    out[start:start + len(claw)] += claw * 0.5
    return out


# --- breathing / vocal (human + monster) ------------------------------------

def breath_exhausted_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    dur = 2.2
    n = int(dur * sr)
    t = np.arange(n) / sr
    rate = 2 / dur
    cyc = (t * rate) % 1.0
    env = np.where(cyc < 0.35, cyc / 0.35, np.clip(1 - (cyc - 0.35) / 0.65, 0, 1))
    noise = rng.standard_normal(n)
    breath = fft_bandpass(noise, sr, 250, 3000)
    return breath * env


def monster_winded_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    dur = 2.8
    n = int(dur * sr)
    t = np.arange(n) / sr
    rate = 3 / dur
    cyc = (t * rate) % 1.0
    env = np.where(cyc < 0.3, (cyc / 0.3) ** 0.5, np.clip(1 - (cyc - 0.3) / 0.7, 0, 1) ** 0.5)
    noise = rng.standard_normal(n)
    wheeze = fft_bandpass(noise, sr, 200, 3500)
    whistle = 0.15 * np.sin(2 * math.pi * 1800 * t + 3 * np.sin(2 * math.pi * 5 * t))
    return (wheeze + whistle) * env


def player_hurt_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    dur = 0.7
    n = int(dur * sr)
    t = np.arange(n) / sr
    f0 = 160 * np.exp(-t * 1.5)
    phase = np.cumsum(2 * math.pi * f0 / sr)
    sig = np.zeros(n)
    for k in range(1, 6):
        sig += np.sin(k * phase) / k
    sig *= np.exp(-t / 0.35)
    sig = formant_filter(sig, sr, 700, 200) + 0.5 * formant_filter(sig, sr, 1400, 300)
    sig += 0.2 * rng.standard_normal(n) * np.exp(-t / 0.2)
    return sig


def player_death_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    dur = 2.2
    n = int(dur * sr)
    t = np.arange(n) / sr
    f0 = 180 * np.exp(-t * 1.1)
    phase = np.cumsum(2 * math.pi * f0 / sr)
    sig = np.zeros(n)
    for k in range(1, 6):
        sig += np.sin(k * phase) / k
    sig *= np.exp(-t / 0.9)
    sig = formant_filter(sig, sr, 650, 220) + 0.4 * formant_filter(sig, sr, 1300, 280)
    sig += 0.15 * rng.standard_normal(n) * np.exp(-t / 0.6)
    return apply_reverb(sig, sr, decay=0.7, dur=0.5, mix=0.25, rng=rng)


def monster_vocal(duration: float, sr: int, rng: np.random.Generator, f0_base=70.0,
                   f0_var=40.0, distortion=0.5, growl_mod=25.0, scream=False) -> np.ndarray:
    n = int(duration * sr)
    t = np.arange(n) / sr
    if scream:
        f0 = f0_base + f0_var * np.clip(t / duration, 0, 1) * 1.3 + 10 * np.sin(2 * math.pi * 6 * t)
        amp_env = np.sin(math.pi * np.clip(t / duration, 0, 1)) ** 0.5
    else:
        f0 = f0_base + f0_var * np.sin(2 * math.pi * growl_mod * t / max(duration, 0.01))
        amp_env = np.ones(n)
    phase = np.cumsum(2 * math.pi * f0 / sr)
    sig = np.zeros(n)
    for k in range(1, 9):
        sig += np.sin(k * phase) / k
    sig += 0.3 * rng.standard_normal(n)
    sig *= amp_env
    sig = formant_filter(sig, sr, 500, 250, dur=0.05) + 0.5 * formant_filter(sig, sr, 1500, 400, dur=0.04)
    return np.tanh(sig * (1 + distortion * 8))


def monster_reveal_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    crack = crack_hit(sr, rng, dur=0.07, band=(300, 10000))
    snaps = np.concatenate([
        crack, np.zeros(int(0.03 * sr)),
        crack * 0.8, np.zeros(int(0.02 * sr)),
        crack * 0.6,
    ])
    scream = monster_vocal(1.6, sr, rng, f0_base=140, f0_var=100, distortion=0.6, scream=True)
    gap = int(0.02 * sr)
    return np.concatenate([snaps, np.zeros(gap), scream])


def abduct_distant_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    scream = monster_vocal(1.2, sr, rng, f0_base=90, f0_var=60, distortion=0.4, scream=True)
    drag = noise_burst(1.0, sr, rng, band=(80, 1500), decay=0.6)
    n = max(len(scream), len(drag))
    out = np.zeros(n)
    out[: len(scream)] += scream * 0.7
    out[: len(drag)] += drag * 0.5
    out = fft_lowpass(out, sr, 1800)
    return apply_reverb(out, sr, decay=1.0, dur=0.8, mix=0.6, rng=rng)


# --- speech-like babble (intercom / walkie) ---------------------------------

VOWEL_FORMANTS = [
    (700, 1200, 90), (300, 2300, 80), (300, 870, 80), (500, 1800, 90), (400, 1000, 70),
]


def glottal_pulse_train(n: int, sr: int, f0_contour: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    phase = np.cumsum(2 * math.pi * f0_contour / sr)
    sig = np.zeros(n)
    for k in range(1, 13):
        sig += np.sin(k * phase) / k
    sig += 0.05 * rng.standard_normal(n)
    return sig


def syllable_envelope(n: int, sr: int, rng: np.random.Generator, pause_prob=0.25) -> np.ndarray:
    dur = n / sr
    n_syllables = max(3, int(dur / 0.22))
    env = np.zeros(n)
    t = np.arange(n) / sr
    pos = 0.0
    for _ in range(n_syllables):
        syl_len = rng.uniform(0.09, 0.22)
        gap = rng.uniform(0.02, 0.08)
        if rng.random() < pause_prob:
            gap += rng.uniform(0.08, 0.2)
        center = pos + syl_len / 2
        width = max(syl_len / 2, 0.02)
        env += np.exp(-0.5 * ((t - center) / (width * 0.6)) ** 2)
        pos += syl_len + gap
        if pos >= dur:
            break
    return np.clip(env, 0, 1)


def make_babble(duration: float, sr: int, rng: np.random.Generator, f0_base=120.0, f0_var=18.0,
                 bandlimit=None, distortion=0.0, static_amt=0.0, pitch_mult=1.0,
                 reverse_syllable_prob=0.0) -> np.ndarray:
    n = int(duration * sr)
    t = np.arange(n) / sr
    steps = rng.normal(0, 1, 40)
    walk = np.cumsum(steps)
    base_contour = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, 40), walk)
    base_contour = base_contour / (np.max(np.abs(base_contour)) + 1e-9)
    f0 = (f0_base * pitch_mult) + base_contour * f0_var
    excitation = glottal_pulse_train(n, sr, f0, rng)
    env = syllable_envelope(n, sr, rng)
    excitation = excitation * env

    chunk_len = int(sr * 0.18)
    step = chunk_len // 2
    acc = np.zeros(n + chunk_len)
    wsum = np.zeros(n + chunk_len)
    win = np.hanning(chunk_len)
    pos = 0
    while pos < n:
        seg = excitation[pos:pos + chunk_len]
        if len(seg) < chunk_len:
            seg = np.pad(seg, (0, chunk_len - len(seg)))
        f1, f2, bw = VOWEL_FORMANTS[rng.integers(0, len(VOWEL_FORMANTS))]
        filtered = (formant_filter(seg, sr, f1, bw, dur=0.05)
                    + 0.6 * formant_filter(seg, sr, f2, bw * 1.3, dur=0.04))
        acc[pos:pos + chunk_len] += filtered[:chunk_len] * win
        wsum[pos:pos + chunk_len] += win
        pos += step
    wsum[wsum < 1e-6] = 1.0
    out = (acc / wsum)[:n]

    if reverse_syllable_prob > 0 and rng.random() < reverse_syllable_prob:
        seg_len = int(sr * rng.uniform(0.12, 0.25))
        start = int(rng.integers(0, max(1, n - seg_len)))
        out[start:start + seg_len] = out[start:start + seg_len][::-1]

    if bandlimit:
        out = fft_bandpass(out, sr, bandlimit[0], bandlimit[1])
    if distortion > 0:
        out = np.tanh(out * (1 + distortion * 6))
    if static_amt > 0:
        lo, hi = bandlimit if bandlimit else (300, 3000)
        static = fft_bandpass(rng.standard_normal(n), sr, lo, hi)
        static = static / (np.max(np.abs(static)) + 1e-9)
        crackle_env = (rng.random(n) < 0.0008).astype(float)
        out = out + static_amt * static * 0.5 + static_amt * crackle_env * rng.standard_normal(n) * 0.8
    return out


def squelch_gen(sr: int, rng: np.random.Generator, rising: bool = True) -> np.ndarray:
    dur = 0.16
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = (800 + 2200 * (t / dur)) if rising else (3000 - 2200 * (t / dur))
    phase = np.cumsum(2 * math.pi * f / sr)
    tone = np.sin(phase)
    noise = fft_bandpass(rng.standard_normal(n), sr, 500, 4000)
    env = np.exp(-t / 0.05)
    return (tone * 0.5 + noise * 0.5) * env


def intercom_chime_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    chime = two_tone_chime(784.0, 523.25, sr, dur_each=0.3, gap=0.05, decay=0.4)
    return apply_reverb(chime, sr, decay=0.5, dur=0.4, mix=0.35, rng=rng)


# --- UI / task / store objects ----------------------------------------------

def locker_open_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    creak = metal_creak_gen(sr, rng, dur=0.5)
    clank = impact_hit(sr, rng, dur=0.15, band=(300, 5000))
    n = max(len(creak), int(0.3 * sr) + len(clank))
    out = np.zeros(n)
    out[: len(creak)] += creak * 0.7
    start = int(0.3 * sr)
    out[start:start + len(clank)] += clank * 0.6
    return out


def tool_pickup_gen(sr: int, rng: np.random.Generator) -> np.ndarray:
    clunk = impact_hit(sr, rng, dur=0.15, band=(300, 4000))
    rustle = box_rustle_gen(sr, rng, dur=0.25)
    n = max(len(clunk), len(rustle))
    out = np.zeros(n)
    out[: len(clunk)] += clunk * 0.6
    out[: len(rustle)] += rustle * 0.4
    return out


def shift_end_bell_gen(sr: int, rng: np.random.Generator, dur: float = 2.0) -> np.ndarray:
    n = int(dur * sr)
    t = np.arange(n) / sr
    partials = [(1.0, 1.0), (2.76, 0.6), (5.4, 0.35), (8.9, 0.2)]
    f0 = 440.0
    sig = np.zeros(n)
    for ratio, amp in partials:
        sig += amp * np.sin(2 * math.pi * f0 * ratio * t) * np.exp(-t / (dur / (1 + ratio * 0.3)))
    return sig


def task_progress_loop_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n) / sr
    rate = 2.0
    phase = (t * rate) % 1.0
    env = np.clip(1 - np.abs(phase - 0.3) / 0.3, 0, 1) ** 1.5
    noise = rng.standard_normal(n)
    scrub = fft_bandpass(noise, sr, 600, 4000)
    sig = scrub * env * 0.8
    sig += 0.1 * np.sin(2 * math.pi * 90 * t)
    return sig


def heartbeat_loop_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    bpm = 80.0
    beat = 60.0 / bpm
    sig = np.zeros(n)
    i = 0
    while True:
        pos = int(i * beat * sr)
        if pos >= n:
            break
        for off, amp, f in [(0.0, 1.0, 55), (0.18, 0.6, 45)]:
            p = pos + int(off * sr)
            pl = int(sr * 0.12)
            if p + pl <= n:
                tt = np.arange(pl) / sr
                pulse = np.sin(2 * math.pi * f * tt) * np.exp(-tt / 0.04)
                sig[p:p + pl] += pulse * amp
        i += 1
    return sig


def breath_loop_gen(n: int, sr: int, rng: np.random.Generator, cycles: int = 2) -> np.ndarray:
    duration = n / sr
    t = np.arange(n) / sr
    rate = cycles / duration
    cyc = (t * rate) % 1.0
    env = np.where(cyc < 0.4, cyc / 0.4, np.clip(1 - (cyc - 0.4) / 0.6, 0, 1)) ** 0.7
    noise = rng.standard_normal(n)
    breath = fft_bandpass(noise, sr, 150, 2500)
    sig = breath * env
    n_crackles = int(duration * 8)
    for _ in range(n_crackles):
        pos = int(rng.integers(0, max(1, n - 300)))
        length = int(rng.integers(60, 250))
        burst = rng.standard_normal(length) * np.exp(-np.arange(length) / 40.0)
        burst = fft_bandpass(burst, sr, 400, 4000) if length > 32 else burst
        end = min(n, pos + length)
        sig[pos:end] += burst[: end - pos] * 0.25 * env[pos]
    return sig


# --- ambience loops ----------------------------------------------------------

def hum_loop_gen(n: int, sr: int, rng: np.random.Generator, f0=120.0,
                  harmonics=((1, 1.0), (2, 0.5), (3, 0.25), (5, 0.1)),
                  noise_level=0.03, crackle=False, crackle_rate=0.5) -> np.ndarray:
    duration = n / sr
    t = np.arange(n) / sr
    sig = np.zeros(n)
    for h, a in harmonics:
        sig += a * np.sin(2 * math.pi * f0 * h * t)
    sig = sig / (np.max(np.abs(sig)) + 1e-9)
    sig += noise_level * rng.standard_normal(n)
    if crackle:
        n_clicks = int(duration * crackle_rate)
        for _ in range(n_clicks):
            pos = int(rng.integers(0, max(1, n - 200)))
            length = int(rng.integers(20, 120))
            burst = rng.standard_normal(length) * np.exp(-np.arange(length) / 15.0)
            end = min(n, pos + length)
            sig[pos:end] += burst[: end - pos] * 0.3
    return sig


def store_hum_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n) / sr
    sig = (0.5 * np.sin(2 * math.pi * 60 * t) + 0.3 * np.sin(2 * math.pi * 120 * t)
           + 0.2 * np.sin(2 * math.pi * 150 * t))
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.6
    noise = fft_bandpass(rng.standard_normal(n), sr, 40, 400)
    return sig + noise * 0.4


def freezer_hum_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    t = np.arange(n) / sr
    base = 0.6 * np.sin(2 * math.pi * 100 * t) + 0.3 * np.sin(2 * math.pi * 200 * t)
    whine = 0.15 * np.sin(2 * math.pi * (2400 + 30 * np.sin(2 * math.pi * 0.2 * t)) * t)
    noise = fft_bandpass(rng.standard_normal(n), sr, 60, 500) * 0.3
    return base + whine + noise


def backroom_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    noise = rng.standard_normal(n)
    rumble = fft_lowpass(noise, sr, 300)
    sig = rumble * 0.6
    duration = n / sr
    n_events = max(1, int(duration / 6))
    for _ in range(n_events):
        pos = int(rng.integers(0, max(1, n - sr)))
        burst = noise_burst(rng.uniform(0.3, 0.8), sr, rng, band=(150, 2000), decay=0.25)
        end = min(n, pos + len(burst))
        sig[pos:end] += burst[: end - pos] * 0.3
    return sig


def dread_drone_gen(n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    duration = n / sr
    t = np.arange(n) / sr
    base = 55.0
    sig = np.zeros(n)
    for d in (1.0, 1.004, 0.997, 2.003, 3.99):
        sig += np.sin(2 * math.pi * base * d * t) / 5
    swell_cycles = max(1, int(duration / 12))
    swell_rate = swell_cycles / duration
    swell = 0.5 + 0.5 * np.sin(2 * math.pi * swell_rate * t - math.pi / 2)
    sig *= (0.4 + 0.6 * swell)
    noise = fft_bandpass(rng.standard_normal(n), sr, 80, 600)
    sig += 0.15 * noise
    n_pulses = max(1, int(duration / 6))
    for _ in range(n_pulses):
        pos = int(rng.integers(0, max(1, n - sr)))
        pl = int(sr * 1.5)
        tt = np.arange(pl) / sr
        pulse = np.sin(2 * math.pi * 40 * tt) * np.exp(-tt / 0.4)
        end = min(n, pos + pl)
        sig[pos:end] += pulse[: end - pos] * 0.4
    return sig


def _dissonant_stab(n: int, sr: int, rng: np.random.Generator, base_freq=220.0) -> np.ndarray:
    t = np.arange(n) / sr
    sig = np.zeros(n)
    for r in (1.0, 1.06, 1.414):
        sig += np.sin(2 * math.pi * base_freq * r * t) / 3
    env = np.exp(-t / (n / sr * 0.5 + 1e-6))
    return sig * env


def chase_music_gen(n: int, sr: int, rng: np.random.Generator, bpm: float = 150.0) -> np.ndarray:
    sig = np.zeros(n)
    beat = 60.0 / bpm
    n_beats = int(n / sr / beat)
    for i in range(n_beats):
        pos = int(i * beat * sr)
        pl = int(sr * 0.25)
        tt = np.arange(pl) / sr
        thump_env = np.exp(-tt / 0.05)
        freq = 60 + (10 if i % 4 == 0 else 0)
        pulse = np.sin(2 * math.pi * freq * tt) * thump_env
        end = min(n, pos + pl)
        sig[pos:end] += pulse[: end - pos] * 0.8
        if i % 2 == 1:
            stab_len = int(sr * 0.15)
            stab = _dissonant_stab(stab_len, sr, rng)
            end2 = min(n, pos + stab_len)
            sig[pos:end2] += stab[: end2 - pos] * 0.5
    hats = fft_bandpass(rng.standard_normal(n), sr, 4000, 10000)
    hat_env = np.zeros(n)
    for i in range(n_beats * 2):
        pos = int(i * beat / 2 * sr)
        pl = int(sr * 0.03)
        if pos + pl < n:
            hat_env[pos:pos + pl] = np.exp(-np.arange(pl) / (sr * 0.008))
    return sig + hats * hat_env * 0.2


# ---------------------------------------------------------------------------
# Manifest: one entry per base path in autoload/sfx.gd SOUNDS
# ---------------------------------------------------------------------------

ONESHOT = []   # (relpath, dir, sr, target_db, fn(sr, rng) -> samples)
LOOP = []      # (relpath, dir, sr, target_db, duration, fn(n, sr, rng) -> samples)


def one(relpath, out_dir, sr, db, fn):
    ONESHOT.append((relpath, out_dir, sr, db, fn))


def loop(relpath, out_dir, sr, db, duration, fn):
    LOOP.append((relpath, out_dir, sr, db, duration, fn))


# Player
for i in range(1, 7):
    one(f"footstep_tile_{i:02d}", SFX_DIR, SR_SFX, -12, lambda sr, rng: footstep_tile_gen(sr, rng))
one("breath_exhausted", SFX_DIR, SR_SFX, -10, lambda sr, rng: breath_exhausted_gen(sr, rng))
loop("heartbeat_loop", SFX_DIR, SR_SFX, -6, 4.5, heartbeat_loop_gen)
one("flashlight_click", SFX_DIR, SR_SFX, -14, lambda sr, rng: click(0.06, sr, rng, band=(1000, 9000)))
one("player_hurt", SFX_DIR, SR_SFX, -8, lambda sr, rng: player_hurt_gen(sr, rng))
one("player_death", SFX_DIR, SR_SFX, -6, lambda sr, rng: player_death_gen(sr, rng))

# Interaction / tasks
loop("task_progress_loop", SFX_DIR, SR_SFX, -14, 4.0, task_progress_loop_gen)
one("task_complete", SFX_DIR, SR_SFX, -8, lambda sr, rng: two_tone_chime(523.25, 659.25, sr, dur_each=0.18, gap=0.03, decay=0.25))
one("task_fail", SFX_DIR, SR_SFX, -8, lambda sr, rng: descending_buzz(sr, rng))
one("tool_pickup", SFX_DIR, SR_SFX, -10, lambda sr, rng: tool_pickup_gen(sr, rng))
one("locker_open", SFX_DIR, SR_SFX, -8, lambda sr, rng: locker_open_gen(sr, rng))
one("locker_close", SFX_DIR, SR_SFX, -8, lambda sr, rng: impact_hit(sr, rng, dur=0.3, band=(200, 5000)))
one("box_rustle", SFX_DIR, SR_SFX, -10, lambda sr, rng: box_rustle_gen(sr, rng))
one("cart_rattle", SFX_DIR, SR_SFX, -9, lambda sr, rng: cart_rattle_gen(sr, rng))
one("time_clock_punch", SFX_DIR, SR_SFX, -8, lambda sr, rng: impact_hit(sr, rng, dur=0.25, band=(200, 6000)))

# Store
for i in range(1, 4):
    one(f"light_flicker_{i:02d}", SFX_DIR, SR_SFX, -10, lambda sr, rng: light_flicker_gen(sr, rng))
for i in range(1, 4):
    one(f"distant_bang_{i:02d}", SFX_DIR, SR_SFX, -6, lambda sr, rng: distant_bang_gen(sr, rng))
for i in range(1, 3):
    one(f"metal_creak_{i:02d}", SFX_DIR, SR_SFX, -9, lambda sr, rng: metal_creak_gen(sr, rng))
one("shift_end_bell", SFX_DIR, SR_SFX, -5, lambda sr, rng: shift_end_bell_gen(sr, rng))

# Manager / radio
one("intercom_chime", SFX_DIR, SR_SFX, -6, lambda sr, rng: intercom_chime_gen(sr, rng))
for i in range(1, 5):
    one(f"intercom_voice_{i:02d}", SFX_DIR, SR_SFX, -7,
        lambda sr, rng: apply_reverb(
            make_babble(2.5, sr, rng, f0_base=rng.uniform(115, 145), bandlimit=(250, 3400)),
            sr, decay=0.6, dur=0.5, mix=0.4, rng=rng))
one("walkie_squelch_on", SFX_DIR, SR_SFX, -9, lambda sr, rng: squelch_gen(sr, rng, rising=True))
one("walkie_squelch_off", SFX_DIR, SR_SFX, -9, lambda sr, rng: squelch_gen(sr, rng, rising=False))
for i in range(1, 7):
    one(f"walkie_voice_{i:02d}", SFX_DIR, SR_SFX, -6,
        lambda sr, rng: make_babble(2.3, sr, rng, f0_base=rng.uniform(100, 150),
                                     bandlimit=(300, 3000), distortion=0.35, static_amt=0.25))
for i in range(1, 4):
    one(f"walkie_voice_mimic_{i:02d}", SFX_DIR, SR_SFX, -6,
        lambda sr, rng: make_babble(2.3, sr, rng, f0_base=rng.uniform(100, 150), pitch_mult=0.94,
                                     bandlimit=(300, 3000), distortion=0.4, static_amt=0.28,
                                     reverse_syllable_prob=1.0))

# Monster
for i in range(1, 5):
    one(f"footstep_monster_{i:02d}", SFX_DIR, SR_SFX, -8, lambda sr, rng: footstep_monster_gen(sr, rng))
loop("monster_breath_loop", SFX_DIR, SR_SFX, -9, 5.0, breath_loop_gen)
one("monster_winded", SFX_DIR, SR_SFX, -6, lambda sr, rng: monster_winded_gen(sr, rng))
one("monster_growl_01", SFX_DIR, SR_SFX, -5,
    lambda sr, rng: monster_vocal(1.8, sr, rng, f0_base=65, f0_var=25, distortion=0.45, growl_mod=6))
one("monster_growl_02", SFX_DIR, SR_SFX, -5,
    lambda sr, rng: monster_vocal(1.6, sr, rng, f0_base=75, f0_var=35, distortion=0.5, growl_mod=9))
one("monster_reveal", SFX_DIR, SR_SFX, -2, lambda sr, rng: monster_reveal_gen(sr, rng))
one("monster_scream", SFX_DIR, SR_SFX, -1,
    lambda sr, rng: monster_vocal(1.8, sr, rng, f0_base=160, f0_var=120, distortion=0.7, scream=True))
one("monster_attack_hit", SFX_DIR, SR_SFX, -4, lambda sr, rng: impact_hit(sr, rng, dur=0.4, band=(100, 7000)))
one("abduct_distant", SFX_DIR, SR_SFX, -10, lambda sr, rng: abduct_distant_gen(sr, rng))
one("chase_stinger", SFX_DIR, SR_SFX, -2, lambda sr, rng: dissonant_cluster(1.5, sr, rng))

# UI
one("ui_click", SFX_DIR, SR_SFX, -18, lambda sr, rng: click(0.04, sr, rng, band=(1500, 9000)))
one("ui_hover", SFX_DIR, SR_SFX, -20, lambda sr, rng: click(0.03, sr, rng, band=(2500, 10000)))

# Ambience (loops, lower sample rate)
loop("amb_store_hum", AMB_DIR, SR_LOOP, -16, 12.0, store_hum_gen)
loop("amb_fluorescent_buzz", AMB_DIR, SR_LOOP, -18, 10.0,
     lambda n, sr, rng: hum_loop_gen(n, sr, rng, f0=120.0, crackle=True, crackle_rate=0.6))
loop("amb_freezer_hum", AMB_DIR, SR_LOOP, -16, 10.0, freezer_hum_gen)
loop("amb_backroom", AMB_DIR, SR_LOOP, -18, 14.0, backroom_gen)

# Music (loops)
loop("music_dread_loop", MUS_DIR, SR_LOOP, -8, 48.0, dread_drone_gen)
loop("music_chase_loop", MUS_DIR, SR_LOOP, -6, 24.0, chase_music_gen)


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def main() -> None:
    count = 0
    for relpath, out_dir, sr, db, fn in ONESHOT:
        rng = seeded_rng(relpath)
        raw = fn(sr, rng)
        samples = finalize(raw, sr, db)
        path = os.path.join(out_dir, relpath + ".wav")
        write_wav(path, samples, sr)
        count += 1
        print(f"  oneshot  {relpath:28s} {len(samples) / sr:6.2f}s  peak {amp_to_db(np.max(np.abs(samples))):6.1f} dBFS")

    for relpath, out_dir, sr, db, duration, fn in LOOP:
        rng = seeded_rng(relpath)
        raw = make_loop(fn, duration, sr, rng)
        samples = finalize(raw, sr, db)
        path = os.path.join(out_dir, relpath + ".wav")
        write_wav(path, samples, sr)
        count += 1
        print(f"  loop     {relpath:28s} {len(samples) / sr:6.2f}s  peak {amp_to_db(np.max(np.abs(samples))):6.1f} dBFS")

    print(f"\nGenerated {count} files.")


if __name__ == "__main__":
    main()
