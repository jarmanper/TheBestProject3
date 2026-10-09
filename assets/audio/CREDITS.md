# Audio credits

Every sound in this project (`assets/audio/sfx/`, `assets/audio/ambience/`,
`assets/audio/music/`) is **100% original, procedurally synthesized audio**.
Nothing here is a recording, sample, or third-party asset; there is nothing to
license or attribute beyond the project itself.

- **Source / author:** generated for this project with
  `art_source/audio/generate_audio.py`, run through Blender's bundled Python
  (numpy-based synthesis: formant filters, FFT band-pass/low-pass/high-pass,
  noise shaping, additive/FM oscillators, convolution reverb). No recordings,
  samples, or CC0 packs (e.g. Kenney.nl, OpenGameArt) were used.
- **Licence:** original work-for-hire for this repository; treat identically
  to the rest of the codebase (no separate licence terms, no non-commercial
  or unknown-licence restrictions).
- **Reproducibility:** every file's synthesis is seeded deterministically from
  its own relative path (`zlib.crc32`), so re-running the generator reproduces
  byte-identical WAVs. Re-run with:
  `blender -b --factory-startup -P art_source/audio/generate_audio.py`

See `.superpowers/sdd/task-4-report.md` for the full per-file table (duration,
peak dBFS, RMS dBFS) and the design notes behind each sound.
