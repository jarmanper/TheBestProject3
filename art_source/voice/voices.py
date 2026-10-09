"""Per-speaker voice settings + SAPI job list for the voice pipeline (stdlib only).

Used by make_jobs (system python3) and process_voices.py (Blender's python, numpy).

  SAPI side   voice     -- installed Windows voice
              rate      -- SpeechSynthesizer.Rate (-10..10, ~11% per step)
  post side   resample  -- playback-rate factor (pitch AND tempo): <1 = lower + slower
              mimic     -- the monster wearing that voice: resample * MIMIC_PITCH (~6% lower and
                           slower), and an unnatural 0.4 s pause right before the place name
"""
import hashlib
import json
import re
import sys

SPEAKERS = {
    #            SAPI voice                 rate  resample
    "MANAGER": {"voice": "Microsoft David Desktop", "rate": -1, "resample": 0.88},
    "DALE":    {"voice": "Microsoft David Desktop", "rate": 2, "resample": 1.0},
    "MARCUS":  {"voice": "Microsoft David Desktop", "rate": 2, "resample": 1.16},
    "RITA":    {"voice": "Microsoft Zira Desktop", "rate": 3, "resample": 1.02},
}
DEFAULT_SPEAKER = {"voice": "Microsoft David Desktop", "rate": 0, "resample": 1.0}
MIMIC_PITCH = 0.94      # ~6% lower (and 6% slower)
MIMIC_RATE_STEP = 0     # extra SAPI rate steps (0: the resample alone makes it ~6% slower)
MIMIC_PAUSE_MS = 400   # final length of the tell after process_voices tightens pauses
MIMIC_BREAK_MS = 1500  # SSML marker break: longer than any natural SAPI pause, so it is findable
PANIC_RATE_STEP = 2     # lines with "!" are said faster

ZONE_PHRASES = [
    "the manager's office", "the janitor closet", "the back hallway", "the storage room",
    "the break room", "customer service", "the checkouts", "frozen foods", "produce", "dairy",
    "Aisle 1", "Aisle 2", "Aisle 3", "Aisle 4", "the store",
]


def clip_key(line):
    return "%s|%s|%d|%s" % (line["channel"], line["speaker"].upper(), int(line["mimic"]), line["text"])


def clip_id(line):
    """Stable file stem for a line: speaker_channel[_mimic]_hash."""
    digest = hashlib.md5(clip_key(line).encode("utf-8")).hexdigest()[:10]
    return "%s_%s%s_%s" % (line["speaker"].lower(), line["channel"], "_mimic" if line["mimic"] else "", digest)


def settings(line):
    return SPEAKERS.get(line["speaker"].upper(), DEFAULT_SPEAKER)


def speech_text(text):
    """Text as the TTS should say it: names in Title case, shouted words lowercased, dashes as commas."""
    text = text.replace("—", ",").replace(" ,", ",")

    def fix(match):
        word = match.group(0)
        if word in ("AM", "PM"):
            return word
        if word in ("DALE", "RITA", "MARCUS"):
            return word.capitalize()
        return word.lower()

    return re.sub(r"\b[A-Z]{2,}\b", fix, text)


def _esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def ssml(line):
    said = speech_text(line["text"])
    body = _esc(said)
    if line["mimic"]:
        # The tell: a beat of dead air right before saying where to go.
        for phrase in ZONE_PHRASES:
            idx = said.rfind(phrase)
            if idx > 0:
                body = _esc(said[:idx]) + '<break time="%dms"/>' % MIMIC_BREAK_MS + _esc(said[idx:])
                break
    return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">%s</speak>' % body


def sapi_rate(line):
    rate = settings(line)["rate"]
    if "!" in line["text"]:
        rate += PANIC_RATE_STEP
    if line["mimic"]:
        rate += MIMIC_RATE_STEP
    return max(-10, min(4, rate))  # walkie chatter is brisk; +5 and up turns to mush


def resample_factor(line):
    factor = settings(line)["resample"]
    if line["mimic"]:
        factor *= MIMIC_PITCH
    return factor


def make_jobs(lines_json, jobs_tsv, win_raw_dir):
    """jobs.tsv: voice \\t rate \\t windows-out-path \\t ssml (one per line)."""
    lines = json.load(open(lines_json, encoding="utf-8"))
    with open(jobs_tsv, "w", encoding="utf-8", newline="\r\n") as out:
        for line in lines:
            out.write("%s\t%d\t%s\\%s.wav\t%s\n" % (
                settings(line)["voice"], sapi_rate(line), win_raw_dir, clip_id(line), ssml(line)))
    print("wrote %d jobs" % len(lines))


if __name__ == "__main__":
    make_jobs(sys.argv[1], sys.argv[2], sys.argv[3])
