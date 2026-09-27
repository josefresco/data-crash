"""Builds assets/audio/music_<track>.ogg: four seamless background loops,
synthesized with numpy (no samples, so they're ours to ship).

  python tools/generate_music.py

- calm: 90 BPM, folksy major (neighborhood, Phase 1)
- assault: 124 BPM, driving minor (datacenter assault)
- build: 100 BPM, hopeful and steady (build phase)
- wave: 138 BPM, tense minor with toms (defense waves)

Each track renders 16 bars plus a tail; the tail is folded back onto the
start so the loop repeats without a seam. Sfx.music() loops them.
"""
from pathlib import Path

import numpy as np
import soundfile
from scipy import signal

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(11)


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def lowpass(x, cutoff, order=2):
    return signal.sosfilt(signal.butter(order, cutoff, btype="low", fs=RATE, output="sos"), x)


def highpass(x, cutoff, order=2):
    return signal.sosfilt(signal.butter(order, cutoff, btype="high", fs=RATE, output="sos"), x)


def band(x, low, high, order=2):
    return signal.sosfilt(signal.butter(order, [low, high], btype="band", fs=RATE, output="sos"), x)


# --- Instruments (mono float arrays) ------------------------------------------

def pluck(midi, seconds, bright=1.0):
    """Guitar-ish pluck: decaying harmonics, the high ones fading first."""
    t = t_axis(seconds)
    f = hz(midi)
    out = np.zeros_like(t)
    for k in range(1, 9):
        if f * k > 9000:
            break
        decay = 0.9 / (k ** 0.8) * bright
        out += np.sin(2 * np.pi * f * k * t + rng.uniform(0, 6.28)) / k * np.exp(-t / decay)
    attack = np.clip(t / 0.004, 0, 1)
    return out * attack


def pad(midis, seconds, cutoff=1800.0):
    """Soft detuned saw chord with slow swell and release."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for m in midis:
        for detune in (-0.08, 0.0, 0.08):
            f = hz(m + detune)
            saw = np.zeros_like(t)
            for k in range(1, 12):
                if f * k > 7000:
                    break
                saw += np.sin(2 * np.pi * f * k * t) / k
            out += saw
    out = lowpass(out, cutoff)
    swell = np.clip(t / (seconds * 0.35), 0, 1) * np.clip((seconds - t) / (seconds * 0.3), 0, 1)
    return out * swell / (len(midis) * 3)


def bass(midi, seconds, grit=0.2):
    t = t_axis(seconds)
    f = hz(midi)
    tone = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + grit * np.sign(np.sin(2 * np.pi * f * t))
    tone = lowpass(tone, 900.0)
    return tone * np.clip(t / 0.006, 0, 1) * np.exp(-t / (seconds * 0.8))


def kick(seconds=0.35):
    t = t_axis(seconds)
    freq = 45 + 90 * np.exp(-t / 0.04)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    return np.sin(phase) * np.exp(-t / 0.16) + 0.3 * np.exp(-t / 0.004) * rng.uniform(-1, 1, len(t))


def snare(seconds=0.25, brush=False):
    t = t_axis(seconds)
    noise = band(rng.uniform(-1, 1, len(t)), 1500 if not brush else 2500, 7500)
    body = 0.5 * np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.05)
    decay = 0.12 if not brush else 0.09
    return (noise * np.exp(-t / decay) + (0.0 if brush else body)) * (0.5 if brush else 1.0)


def hat(seconds=0.08, open_hat=False):
    t = t_axis(seconds)
    noise = highpass(rng.uniform(-1, 1, len(t)), 7000.0, 4)
    return noise * np.exp(-t / (0.09 if open_hat else 0.025)) * 0.5


def tom(midi, seconds=0.4):
    t = t_axis(seconds)
    f0 = hz(midi)
    freq = f0 * (1 + 0.6 * np.exp(-t / 0.05))
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    return np.sin(phase) * np.exp(-t / 0.18)


# --- Sequencing -------------------------------------------------------------------

class Track:
    def __init__(self, bpm, bars, beats_per_bar=4, tail=2.0):
        self.beat = 60.0 / bpm
        self.length = bars * beats_per_bar * self.beat
        self.buf = np.zeros((int(RATE * (self.length + tail)), 2))

    def add(self, sound, beat, gain=1.0, pan=0.0):
        """Mixes a mono `sound` at `beat` (float), panned -1..1."""
        i = int(RATE * beat * self.beat)
        n = min(len(sound), len(self.buf) - i)
        if n <= 0:
            return
        left = gain * np.cos((pan + 1) * np.pi / 4)
        right = gain * np.sin((pan + 1) * np.pi / 4)
        self.buf[i:i + n, 0] += sound[:n] * left
        self.buf[i:i + n, 1] += sound[:n] * right

    def render(self, name, peak=0.8):
        n = int(RATE * self.length)
        out = self.buf[:n].copy()
        tail = self.buf[n:]
        out[:len(tail)] += tail  # fold the ring-out onto the start: seamless loop
        out = np.tanh(out / max(np.max(np.abs(out)), 1e-6) * 1.2) / np.tanh(1.2) * peak
        OUT.mkdir(parents=True, exist_ok=True)
        path = OUT / f"music_{name}.ogg"
        # Block writes: one huge Vorbis write crashes some libsndfile builds.
        with soundfile.SoundFile(str(path), "w", RATE, 2, format="OGG", subtype="VORBIS") as f:
            for start in range(0, len(out), 8192):
                f.write(np.ascontiguousarray(out[start:start + 8192], dtype=np.float32))
        print(f"wrote {path.name}: {self.length:.1f}s")


def chord(root, minor=False):
    third = 3 if minor else 4
    return [root, root + third, root + 7]


def calm():
    tr = Track(90, 16)
    prog = [(60, False), (57, True), (53, False), (55, False)]  # C Am F G
    melody = [76, 74, 72, 74, 76, 79, 76, 74, 72, 69, 72, 74, 72, 67, 69, 72]
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = chord(root, minor)
        b0 = bar * 4
        tr.add(pad([n - 12 for n in notes] + [notes[0]], tr.beat * 4.5), b0, 0.35)
        tr.add(bass(root - 24, tr.beat * 1.8), b0, 0.55)
        tr.add(bass(root - 17, tr.beat * 1.8), b0 + 2, 0.45)
        # Fingerpicked arpeggio in eighths.
        pattern = [notes[0], notes[1], notes[2], notes[1] + 12, notes[2], notes[1], notes[0] + 12, notes[2]]
        for k, n in enumerate(pattern):
            tr.add(pluck(n, 1.4), b0 + k * 0.5, 0.28, pan=0.35)
        tr.add(snare(brush=True), b0 + 1, 0.35, pan=-0.2)
        tr.add(snare(brush=True), b0 + 3, 0.35, pan=-0.2)
        for k in range(8):
            tr.add(hat(), b0 + k * 0.5 + 0.02, 0.12 if k % 2 else 0.18, pan=0.25)
        # A simple whistled-sounding tune on alternate phrases.
        if (bar // 4) % 2 == 1:
            for k in range(2):
                n = melody[(bar * 2 + k) % len(melody)]
                tr.add(pluck(n, 1.6, bright=1.6), b0 + k * 2, 0.3, pan=-0.35)
    tr.render("calm")


def assault():
    tr = Track(124, 16)
    prog = [(57, True), (53, False), (48, False), (55, False)]  # Am F C G
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = chord(root, minor)
        b0 = bar * 4
        tr.add(pad(notes, tr.beat * 4.2, cutoff=2400.0), b0, 0.3)
        for k in range(8):
            tr.add(bass(root - 24 + (12 if k in (3, 7) else 0), tr.beat * 0.45, grit=0.45), b0 + k * 0.5, 0.5)
        for beat in (0, 1.5, 2, 3.5) if bar % 2 else (0, 2, 2.75):
            tr.add(kick(), b0 + beat, 0.9)
        tr.add(snare(), b0 + 1, 0.55, pan=0.1)
        tr.add(snare(), b0 + 3, 0.55, pan=0.1)
        for k in range(16):
            tr.add(hat(open_hat=(k % 4 == 2)), b0 + k * 0.25, 0.14 if k % 2 else 0.2, pan=0.3)
        # Stabs on the offbeats in the second half.
        if bar >= 8:
            for beat in (0.5, 2.5):
                for n in notes:
                    tr.add(pluck(n + 12, 0.35, bright=0.4), b0 + beat, 0.16, pan=-0.3)
    tr.render("assault")


def build():
    tr = Track(100, 16)
    prog = [(55, False), (52, True), (48, False), (50, False)]  # G Em C D
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = chord(root, minor)
        b0 = bar * 4
        tr.add(pad([n - 12 for n in notes] + [notes[1] + 12], tr.beat * 4.4, cutoff=1500.0), b0, 0.4)
        tr.add(bass(root - 24, tr.beat * 0.9), b0, 0.5)
        tr.add(bass(root - 24, tr.beat * 0.9), b0 + 1.5, 0.35)
        tr.add(bass(root - 17, tr.beat * 0.9), b0 + 2.5, 0.4)
        # A steady sixteenth arpeggio: the "getting to work" feel.
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[1] + 12]
        for k in range(16):
            tr.add(pluck(arp[k % 4], 0.5, bright=0.5), b0 + k * 0.25, 0.14, pan=(0.4 if k % 2 else -0.4))
        tr.add(kick(), b0, 0.6)
        tr.add(kick(), b0 + 2, 0.5)
        tr.add(snare(brush=True), b0 + 1, 0.4)
        tr.add(snare(brush=True), b0 + 3, 0.4)
    tr.render("build")


def wave():
    tr = Track(138, 16)
    prog = [(52, True), (48, False), (50, False), (47, False)]  # Em C D B
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = chord(root, minor or root == 47)
        b0 = bar * 4
        tr.add(pad(notes + [notes[0] + 12], tr.beat * 4.2, cutoff=3000.0), b0, 0.28)
        for k in range(16):
            tr.add(bass(root - 24, tr.beat * 0.22, grit=0.6), b0 + k * 0.25, 0.42 if k % 4 else 0.55)
        for beat in (0, 1, 2, 3):
            tr.add(kick(), b0 + beat, 0.85)
        tr.add(snare(), b0 + 1, 0.6)
        tr.add(snare(), b0 + 3, 0.6)
        for k in range(8):
            tr.add(hat(), b0 + k * 0.5 + 0.25, 0.18, pan=0.35)
        if bar % 4 == 3:
            for k, m in enumerate((50, 47, 45, 43)):
                tr.add(tom(m), b0 + 2 + k * 0.5, 0.55, pan=-0.5 + k * 0.33)
        # A rising alarm line every other phrase.
        if (bar // 4) % 2 == 1:
            for k in range(4):
                tr.add(pluck(notes[k % 3] + 24, 0.3, bright=0.3), b0 + k + 0.5, 0.14, pan=-0.2)
    tr.render("wave")


def main():
    calm()
    assault()
    build()
    wave()


if __name__ == "__main__":
    main()
