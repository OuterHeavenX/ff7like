#!/usr/bin/env python3
"""Deterministic original music and SFX synthesizer for Echoes of the Last Dawn.

All melodies are composed for this project and written out below as note data.
Music renders to seamless-looping OGG (loop wraps the delay tail to the start);
SFX render to short 16-bit WAV. Requires numpy and ffmpeg.

Run: python3 tools/gen_audio.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUSIC = os.path.join(ROOT, "assets", "audio", "music")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
              "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def freq(name):
    if name in ("R", "-"):
        return 0.0
    n, o = name[:-1], int(name[-1])
    midi = 12 * (o + 1) + NOTE_INDEX[n]
    return 440.0 * 2 ** ((midi - 69) / 12)


def midi_freq(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ------------------------------------------------------------------ oscillators

def osc(kind, f, n, duty=0.5):
    t = np.arange(n) / SR
    if f <= 0:
        return np.zeros(n)
    ph = (t * f) % 1.0
    if kind == "pulse":
        return np.where(ph < duty, 1.0, -1.0) * 0.6
    if kind == "tri":
        return (4 * np.abs(ph - 0.5) - 1.0)
    if kind == "saw":
        return (2 * ph - 1) * 0.5
    if kind == "sine":
        return np.sin(2 * np.pi * f * t)
    if kind == "flute":
        return np.sin(2 * np.pi * f * t) * 0.8 + 0.2 * np.sin(4 * np.pi * f * t) + 0.04 * np.sin(2 * np.pi * 5.5 * t) * np.sin(2 * np.pi * f * t)
    if kind == "organ":
        return (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(4 * np.pi * f * t) + 0.25 * np.sin(6 * np.pi * f * t)) / 1.75
    if kind == "bell":
        env2 = np.exp(-t * 3)
        return (np.sin(2 * np.pi * f * t) + 0.6 * env2 * np.sin(2 * np.pi * f * 2.76 * t) + 0.4 * env2 * np.sin(2 * np.pi * f * 5.4 * t)) / 2.0
    raise ValueError(kind)


def pluck(f, n, decay=0.996):
    if f <= 0:
        return np.zeros(n)
    period = max(2, int(SR / f))
    rng = np.random.default_rng(int(f * 100))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = decay * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out


def env(n, a=0.01, d=0.08, s=0.7, r=0.08):
    e = np.ones(n) * s
    ai, di, ri = int(a * SR), int(d * SR), int(r * SR)
    ai = min(ai, n)
    e[:ai] = np.linspace(0, 1, ai) if ai > 0 else e[:ai]
    end = min(n, ai + di)
    if end > ai:
        e[ai:end] = np.linspace(1, s, end - ai)
    if ri > 0 and ri < n:
        e[n - ri:] *= np.linspace(1, 0, ri)
    return e


def noise(n, seed=0):
    return np.random.default_rng(seed).uniform(-1, 1, n)


# ------------------------------------------------------------------ sequencing

class Song:
    def __init__(self, bpm, beats):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.n = int(round(beats * self.beat * SR))
        self.mix = np.zeros(self.n)

    def add(self, sig, start_beat, gain):
        s = int(round(start_beat * self.beat * SR))
        if s >= self.n:
            return
        e = min(self.n, s + len(sig))
        self.mix[s:e] += sig[:e - s] * gain
        # wrap overflow to the beginning for seamless loops
        if s + len(sig) > self.n:
            over = sig[e - s:]
            k = min(len(over), self.n)
            self.mix[:k] += over[:k] * gain

    def line(self, notes, inst, gain, start=0.0, adsr=(0.01, 0.1, 0.7, 0.08), octave_shift=0, duty=0.5, legato=0.95):
        """notes: 'E4:1 G4:.5 R:.5' style string."""
        b = start
        for tok in notes.split():
            name, dur = tok.split(":")
            dur = float(dur)
            if name not in ("R", "-"):
                f = freq(name) * (2 ** octave_shift)
                n = int(dur * legato * self.beat * SR)
                if inst == "pluck":
                    sig = pluck(f, n + int(0.3 * SR))
                    sig *= env(len(sig), 0.002, 0.05, 0.8, 0.2)
                else:
                    sig = osc(inst, f, n, duty) * env(n, *adsr)
                self.add(sig, b, gain)
            b += dur
        return b

    def chords(self, prog, beats_each, inst, gain, kind="pad", octave=3, pattern=None):
        """prog: list of chord symbols e.g. ['Dm','Bb','F','C']."""
        b = 0.0
        for ch in prog:
            root, quality = parse_chord(ch)
            base = 12 * (octave + 1) + root
            ints = {"maj": [0, 4, 7], "min": [0, 3, 7], "sus": [0, 5, 7], "dim": [0, 3, 6], "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "7": [0, 4, 7, 10]}[quality]
            if kind == "pad":
                n = int(beats_each * self.beat * SR)
                sig = sum(osc("tri", midi_freq(base + i), n) * 0.33 + osc("sine", midi_freq(base + i + 12), n) * 0.15 for i in ints)
                sig *= env(n, 0.25, 0.3, 0.8, 0.3)
                self.add(sig, b, gain)
            elif kind == "arp":
                pat = pattern or [0, 1, 2, 1]
                step = beats_each / (len(pat) * 2)
                notes = ints + [i + 12 for i in ints]
                for k in range(len(pat) * 2):
                    idx = min(len(notes) - 1, pat[k % len(pat)] + (len(ints) if k >= len(pat) else 0))
                    m = base + 12 + notes[idx]
                    n = int(step * self.beat * SR * 1.6)
                    sig = (pluck(midi_freq(m), n) if inst == "pluck" else osc(inst, midi_freq(m), n) * env(n, 0.005, 0.1, 0.4, 0.1))
                    self.add(sig, b + k * step, gain)
            elif kind == "bass":
                pat = pattern or [(0, 1.0)]
                t = 0.0
                while t < beats_each - 1e-6:
                    for (iv, d) in pat:
                        if t >= beats_each - 1e-6:
                            break
                        n = int(d * 0.9 * self.beat * SR)
                        sig = osc(inst, midi_freq(base - 12 + iv), n, 0.25) * env(n, 0.005, 0.08, 0.6, 0.05)
                        self.add(sig, b + t, gain)
                        t += d
            elif kind == "oompah":
                # waltz: bass on 1, chord on 2 and 3
                n1 = int(0.9 * self.beat * SR)
                self.add(osc(inst, midi_freq(base - 12), n1) * env(n1, 0.005, 0.1, 0.5, 0.05), b, gain)
                for beat in (1, 2):
                    sig = sum(osc(inst, midi_freq(base + i), n1 // 2) for i in ints) / 3
                    self.add(sig * env(n1 // 2, 0.005, 0.05, 0.4, 0.05), b + beat, gain * 0.6)
            b += beats_each

    def drums(self, pattern, bars, beats_per_bar, gain):
        """pattern: dict of step-strings over 16ths of one bar: {'k':'x...x...', 's':..., 'h':...}."""
        steps = len(next(iter(pattern.values())))
        step_beats = beats_per_bar / steps
        for bar in range(bars):
            for inst, pat in pattern.items():
                for i, ch in enumerate(pat):
                    if ch == ".":
                        continue
                    acc = 1.0 if ch == "X" else 0.7
                    sig = drum(inst)
                    self.add(sig * acc, bar * beats_per_bar + i * step_beats, gain)

    def delay(self, time_beats=0.75, fb=0.3, mix=0.25):
        d = int(time_beats * self.beat * SR)
        out = self.mix.copy()
        for k in range(1, 4):
            out += np.roll(self.mix, d * k) * (fb ** k) * mix / fb
        self.mix = out

    def render(self, path, peak=0.85):
        m = self.mix
        mx = np.max(np.abs(m)) or 1.0
        m = np.tanh(m / mx * 1.2) / np.tanh(1.2) * peak
        write_wav(path + ".wav", m)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path + ".wav", "-c:a", "libvorbis", "-q:a", "3", path + ".ogg"], check=True)
        os.remove(path + ".wav")


def parse_chord(ch):
    if len(ch) > 1 and ch[1] in "#b":
        root, rest = ch[:2], ch[2:]
    else:
        root, rest = ch[:1], ch[1:]
    q = {"": "maj", "m": "min", "sus": "sus", "dim": "dim", "maj7": "maj7", "m7": "min7", "7": "7"}[rest]
    return NOTE_INDEX[root], q


_drum_cache = {}


def drum(kind):
    if kind in _drum_cache:
        return _drum_cache[kind]
    if kind == "k":
        n = int(0.18 * SR)
        t = np.arange(n) / SR
        f = 110 * np.exp(-t * 25) + 45
        sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)
    elif kind == "s":
        n = int(0.16 * SR)
        t = np.arange(n) / SR
        sig = noise(n, 3) * np.exp(-t * 22) * 0.6 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.4
    elif kind == "h":
        n = int(0.05 * SR)
        t = np.arange(n) / SR
        sig = noise(n, 5) * np.exp(-t * 80) * 0.35
        sig = np.diff(np.concatenate([[0], sig]))
    elif kind == "t":
        n = int(0.2 * SR)
        t = np.arange(n) / SR
        sig = np.sin(2 * np.pi * (140 * np.exp(-t * 8) + 70) * t) * np.exp(-t * 12)
    elif kind == "c":  # soft bell/chime percussion
        n = int(0.5 * SR)
        sig = osc("bell", 1760, n) * np.exp(-np.arange(n) / SR * 6) * 0.3
    else:
        sig = np.zeros(10)
    _drum_cache[kind] = sig
    return sig


def write_wav(path, data):
    d = np.clip(data, -1, 1)
    pcm = (d * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------ compositions (original)

def title():
    s = Song(76, 64)
    prog = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"] * 2
    s.chords(prog, 4, "tri", 0.35, "pad", 3)
    s.chords(prog, 4, "pluck", 0.22, "arp", 3, [0, 1, 2, 3])
    mel = ("R:4 A4:1.5 G4:.5 F4:1 E4:1 D4:3 R:1 F4:1.5 G4:.5 A4:1 C5:1 "
           "A4:3 R:1 D5:1.5 C5:.5 Bb4:1 A4:1 G4:2 F4:1 G4:1 A4:4 "
           "R:4 A4:1.5 Bb4:.5 C5:1 D5:1 F5:3 R:1 E5:1.5 D5:.5 C5:1 A4:1 "
           "D5:3 R:1 Bb4:1.5 A4:.5 G4:1 F4:1 E4:2 G4:2 A4:4")
    s.line(mel, "flute", 0.32, 0, (0.06, 0.2, 0.75, 0.2))
    s.delay(0.75, 0.35, 0.3)
    return s


def town():
    # "Lanternwake" — a festival waltz in G
    s = Song(138, 96)
    prog = ["G", "G", "C", "D", "Em", "C", "D", "G", "G", "Bm", "C", "G", "Am", "D", "G", "D",
            "C", "D", "Bm", "Em", "Am", "D", "G", "G", "C", "G", "Am", "D", "Em", "C", "D", "G"]
    s.chords(prog, 3, "tri", 0.3, "oompah", 3)
    mel = ("D5:1 B4:1 G4:1 A4:1.5 B4:.5 C5:1 E5:2 D5:1 C5:2 A4:1 B4:3 "
           "G4:1 A4:1 B4:1 C5:2 B4:1 A4:1 B4:1 C5:1 D5:3 R:3 "
           "D5:1 E5:1 F#5:1 G5:2 D5:1 E5:1.5 D5:.5 B4:1 G4:3 "
           "C5:1 B4:1 A4:1 B4:2 G4:1 A4:3 R:3 "
           "E5:1 D5:1 C5:1 D5:2 A4:1 B4:1 C5:1 D5:1 E5:3 "
           "C5:1.5 B4:.5 A4:1 D5:3 G4:3 R:3 "
           "E5:1.5 F#5:.5 G5:1 D5:2 B4:1 C5:1 B4:1 A4:1 G4:2 B4:1 "
           "A4:1 B4:1 C5:1 B4:2 A4:1 G4:3 R:3")
    s.line(mel, "flute", 0.3, 0, (0.02, 0.1, 0.7, 0.08))
    s.drums({"c": "x..", "h": ".x."}, 32, 3, 0.15)
    s.delay(1.0, 0.25, 0.2)
    return s


def undercroft():
    s = Song(84, 64)
    prog = ["Am", "Am", "F", "E", "Am", "Dm", "F", "E"] * 2
    s.chords(prog, 4, "tri", 0.3, "pad", 2)
    s.chords(prog, 4, "pulse", 0.12, "bass", 3, [(0, 1.0), (7, 0.5), (0, 0.5), (12, 1.0), (7, 1.0)])
    drip = "E6:.5 R:3.5 R:1 B5:.5 R:2.5 R:2 C6:.5 R:1.5 R:4 " * 2
    s.line(drip * 2, "bell", 0.08, 0)
    mel = ("R:8 E4:2 F4:1 E4:1 D4:2 C4:2 B3:4 R:4 "
           "A3:2 C4:2 E4:3 D4:1 F4:4 E4:2 D4:1 C4:1 B3:4 R:4 "
           "E4:2 F4:1 G#4:1 A4:4 R:4")
    s.line(mel, "sine", 0.2, 0, (0.15, 0.2, 0.6, 0.3))
    s.delay(1.5, 0.4, 0.35)
    return s


def battle():
    s = Song(156, 64)
    prog = ["Em", "Em", "C", "D", "Em", "Em", "Am", "B", "C", "D", "Bm", "Em", "C", "D", "B", "B"]
    s.chords(prog, 4, "pulse", 0.28, "bass", 2, [(0, 0.5), (0, 0.5), (12, 0.5), (0, 0.5), (7, 0.5), (0, 0.5), (10, 0.5), (12, 0.5)])
    s.chords(prog, 4, "saw", 0.16, "pad", 3)
    mel = ("E5:1.5 B4:.5 E5:1 F#5:1 G5:1.5 F#5:.5 E5:1 D5:1 E5:3 B4:1 G4:2 A4:2 "
           "B4:1.5 E5:.5 G5:1 F#5:1 E5:1.5 D5:.5 B4:2 C5:2 E5:2 D#5:4 "
           "C5:1 D5:1 E5:1 G5:1 F#5:2 D5:2 B4:1 C5:1 D5:1 F#5:1 B4:4 "
           "C5:1.5 B4:.5 A4:1 G4:1 F#4:2 A4:2 B4:6 D#5:2")
    s.line(mel, "pulse", 0.24, 0, (0.005, 0.08, 0.6, 0.05), duty=0.25)
    s.drums({"k": "X...x...X...x...", "s": "....X.......X..x", "h": "x.x.x.x.x.x.x.x."}, 16, 4, 0.35)
    return s


def boss():
    s = Song(168, 64)
    prog = ["Cm", "Cm", "Ab", "Bb", "Cm", "Cm", "Fm", "G", "Ab", "Bb", "Gm", "Cm", "Ab", "Fm", "G", "G"]
    s.chords(prog, 4, "saw", 0.3, "bass", 2, [(0, 0.25), (0, 0.25), (12, 0.5), (0, 0.25), (0, 0.25), (10, 0.5), (0, 0.5), (7, 0.5), (12, 0.5), (0, 0.5)])
    s.chords(prog, 4, "organ", 0.18, "pad", 3)
    mel = ("C5:1 Eb5:1 G5:1 C6:1 B5:2 G5:2 Ab5:1.5 G5:.5 F5:1 Eb5:1 D5:4 "
           "C5:1 D5:1 Eb5:1 F5:1 G5:2 Eb5:2 F5:1.5 Eb5:.5 D5:1 C5:1 B4:4 "
           "Ab4:1 C5:1 Eb5:1 Ab5:1 G5:2 F5:2 G5:1 F5:1 Eb5:1 D5:1 C5:4 "
           "Ab5:2 G5:2 F5:2 Eb5:2 D5:4 G4:2 B4:2")
    s.line(mel, "pulse", 0.24, 0, (0.005, 0.06, 0.65, 0.05), duty=0.125)
    s.line("C6:.5 R:3.5 " * 16, "bell", 0.12, 0)
    s.drums({"k": "X..xX...X..xX.x.", "s": "....X.......X...", "h": "xxxxxxxxxxxxxxxx", "t": "..............XX"}, 16, 4, 0.38)
    return s


def wren():
    # Sister's theme — gentle, in F
    s = Song(66, 64)
    prog = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "C", "Dm", "Am", "Bb", "F", "Gm", "C", "F", "F"]
    s.chords(prog, 4, "pluck", 0.26, "arp", 3, [0, 1, 2, 1])
    s.chords(prog, 4, "tri", 0.2, "pad", 3)
    mel = ("A4:2 G4:1 F4:1 G4:3 C4:1 D4:1.5 E4:.5 F4:1 A4:1 G4:4 "
           "A4:2 C5:1 Bb4:1 A4:2 G4:1 F4:1 D4:2 F4:1 G4:1 E4:4 "
           "F4:1 G4:1 A4:1 C5:1 D5:3 C5:1 Bb4:1.5 A4:.5 G4:1 F4:1 A4:4 "
           "Bb4:2 A4:1 G4:1 C5:3 E4:1 F4:8")
    s.line(mel, "flute", 0.3, 0, (0.08, 0.2, 0.75, 0.25))
    s.delay(1.0, 0.35, 0.3)
    return s


def tension():
    s = Song(70, 32)
    s.chords(["Dm", "Eb", "Dm", "Dm"] * 2, 4, "tri", 0.4, "pad", 2)
    s.line(("D3:8 Eb3:8 " * 2), "saw", 0.12, 0, (1.0, 0.5, 0.8, 1.0))
    s.line("A5:.5 R:7.5 Bb5:.5 R:7.5 " * 2, "bell", 0.1, 0)
    s.drums({"t": "X.......", "h": "....x..."}, 16, 2, 0.15)
    return s


def victory():
    # Original short fanfare loop (rising fourths, resolving on a sustained chord).
    s = Song(120, 16)
    s.chords(["C", "F", "G", "C"], 4, "tri", 0.3, "pad", 3)
    s.line("G4:.5 C5:.5 F5:1 E5:.5 D5:.5 C5:1 A4:.5 C5:.5 F5:1 G5:1 E5:1 D5:1 C5:.5 D5:.5 E5:1 C5:4 R:2",
           "pulse", 0.26, 0, (0.005, 0.08, 0.7, 0.06), duty=0.25)
    s.drums({"k": "X...X...", "s": "....X...", "h": "x.x.x.x."}, 4, 4, 0.25)
    return s


def bells_ambient():
    s = Song(60, 32)
    s.chords(["F", "Am", "Bb", "C"] * 2, 4, "tri", 0.25, "pad", 3)
    s.line("F5:2 R:2 C5:2 R:2 A5:2 R:6 G5:2 R:2 E5:2 R:4 " * 2, "bell", 0.18, 0)
    s.delay(1.5, 0.45, 0.4)
    return s


TRACKS = {"title": title, "town_bellweather": town, "dungeon_undercroft": undercroft,
          "battle": battle, "boss": boss, "theme_wren": wren, "tension": tension,
          "victory": victory, "bells": bells_ambient}


# ------------------------------------------------------------------ sfx

def sfx_all():
    out = {}
    def tone(f0, f1, dur, kind="pulse", vol=0.5, a=0.002, r=0.05):
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = np.linspace(f0, f1, n)
        ph = np.cumsum(f) / SR
        if kind == "pulse":
            sig = np.where(ph % 1 < 0.5, 1.0, -1.0) * 0.5
        elif kind == "sine":
            sig = np.sin(2 * np.pi * ph)
        else:
            sig = 4 * np.abs(ph % 1 - 0.5) - 1
        return sig * env(n, a, 0.02, 0.8, r) * vol
    out["cursor"] = tone(1200, 1200, 0.03, "pulse", 0.25)
    out["confirm"] = np.concatenate([tone(880, 880, 0.04, "pulse", 0.3), tone(1320, 1320, 0.06, "pulse", 0.3)])
    out["cancel"] = np.concatenate([tone(700, 700, 0.04, "pulse", 0.3), tone(480, 480, 0.06, "pulse", 0.3)])
    out["error"] = tone(180, 160, 0.18, "pulse", 0.3)
    n = int(0.12 * SR)
    out["hit"] = noise(n, 1) * np.exp(-np.arange(n) / SR * 30) * 0.7 + tone(200, 60, 0.12, "sine", 0.6)
    out["slash"] = noise(int(0.15 * SR), 2) * np.linspace(0, 1, int(0.15 * SR)) ** 0.5 * np.exp(-np.arange(int(0.15 * SR)) / SR * 18) * 0.6
    out["crit"] = np.concatenate([out["hit"], tone(1600, 2400, 0.12, "pulse", 0.25)])
    out["magic"] = tone(400, 1600, 0.35, "sine", 0.4, 0.01, 0.15) + tone(800, 3200, 0.35, "sine", 0.15, 0.01, 0.15)
    nf = int(0.4 * SR)
    out["fire"] = noise(nf, 4) * np.exp(-np.arange(nf) / SR * 6) * 0.5 * (1 + np.sin(np.arange(nf) / SR * 2 * np.pi * 30)) / 2
    out["frost"] = sum(tone(f, f * 1.01, 0.4, "sine", 0.15, 0.002, 0.3) for f in (2093, 2637, 3136))
    nb = int(0.35 * SR)
    out["storm"] = noise(nb, 6) * (np.random.default_rng(7).random(nb) > 0.7) * np.exp(-np.arange(nb) / SR * 8) * 0.8
    out["heal"] = np.concatenate([tone(f, f, 0.08, "sine", 0.35) for f in (784, 988, 1175, 1568)])
    out["buff"] = tone(500, 1000, 0.25, "tri", 0.4)
    out["debuff"] = tone(900, 300, 0.3, "tri", 0.4)
    out["item"] = np.concatenate([tone(1047, 1047, 0.06, "sine", 0.3), tone(1568, 1568, 0.1, "sine", 0.3)])
    out["chest"] = np.concatenate([tone(f, f, 0.07, "pulse", 0.25) for f in (523, 659, 784, 1047)])
    ns = int(0.05 * SR)
    out["step"] = noise(ns, 8) * np.exp(-np.arange(ns) / SR * 90) * 0.15
    nbell = int(2.5 * SR)
    out["bell"] = osc("bell", 220, nbell) * np.exp(-np.arange(nbell) / SR * 1.4) * 0.8
    out["bell_wrong"] = (osc("bell", 220, nbell) + osc("bell", 233, nbell)) * np.exp(-np.arange(nbell) / SR * 1.2) * 0.5
    out["encounter"] = np.concatenate([tone(f, f * 0.98, 0.07, "pulse", 0.3) for f in (440, 554, 659, 880, 659, 880)])
    out["levelup"] = np.concatenate([tone(f, f, 0.09, "pulse", 0.3) for f in (523, 659, 784, 1047, 1319)])
    out["escape"] = tone(800, 200, 0.4, "pulse", 0.25)
    out["ko"] = tone(400, 80, 0.5, "tri", 0.4)
    out["door"] = noise(int(0.2 * SR), 9) * np.exp(-np.arange(int(0.2 * SR)) / SR * 15) * 0.3 + tone(120, 90, 0.2, "sine", 0.4)
    out["save"] = np.concatenate([tone(f, f, 0.12, "sine", 0.3) for f in (659, 880, 1319)])
    out["resonance"] = sum(tone(f, f * 1.5, 0.6, "sine", 0.2, 0.05, 0.3) for f in (330, 495, 660))
    out["guard"] = tone(300, 300, 0.1, "pulse", 0.3) + noise(int(0.1 * SR), 10) * 0.1
    out["coin"] = np.concatenate([tone(1976, 1976, 0.05, "pulse", 0.2), tone(2637, 2637, 0.12, "pulse", 0.2)])
    out["warning"] = np.concatenate([tone(600, 600, 0.12, "pulse", 0.3), np.zeros(int(0.05 * SR)), tone(600, 600, 0.12, "pulse", 0.3)])
    out["talk"] = tone(660, 660, 0.02, "pulse", 0.08)
    return out


def main():
    os.makedirs(MUSIC, exist_ok=True)
    os.makedirs(SFX, exist_ok=True)
    for name, fn in TRACKS.items():
        s = fn()
        s.render(os.path.join(MUSIC, name))
        print("music", name, round(s.n / SR, 1), "s")
    for name, sig in sfx_all().items():
        sig = np.asarray(sig, dtype=float)
        mx = np.max(np.abs(sig)) or 1
        write_wav(os.path.join(SFX, name + ".wav"), sig / mx * 0.7)
    print("sfx done")


if __name__ == "__main__":
    main()
