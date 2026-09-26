"""Builds assets/audio/: synthesized cues plus picks from Kenney CC0 audio packs.

Every cue is saved as <cue>_<n>.wav (synthesized) or <cue>_<n>.ogg (Kenney),
where n counts random variants. Sfx (scripts/autoload/sfx.gd) finds them by
name. Loops are written with whole cycles / crossfaded ends so they repeat
cleanly.

  python tools/generate_sfx.py --kenney <dir with the unzipped kenney_* packs>

Kenney packs used (kenney.nl, CC0): Impact Sounds, Interface Sounds,
Sci-fi Sounds, Music Jingles. Without --kenney only the synthesized cues are
rebuilt.
"""
import argparse
import shutil
import wave
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def band(x, low, high, order=2):
    sos = signal.butter(order, [low, high], btype="band", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype="low", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, btype="high", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def env(seconds, attack, decay):
    t = t_axis(seconds)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-np.maximum(t - attack, 0.0) / decay)


def fit(x, seconds):
    n = int(RATE * seconds)
    return x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))


def echo(x, delay, gain, taps=3):
    out = np.copy(x)
    step = int(RATE * delay)
    for i in range(1, taps + 1):
        if step * i >= len(x):
            break
        shifted = np.zeros_like(x)
        shifted[step * i:] = x[:len(x) - step * i] * gain ** i
        out += lowpass(shifted, 2500.0)
    return out


def save(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    top = np.max(np.abs(x))
    if top > 0:
        x = x / top * peak
    data = (np.clip(x, -1.0, 1.0) * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())


def loopable(x, fade=0.25):
    """Crossfades the tail into the head so the clip repeats without a click."""
    n = int(RATE * fade)
    head, tail = x[:n], x[-n:]
    ramp = np.linspace(0.0, 1.0, n)
    body = x[n:-n] if len(x) > 2 * n else x[n:]
    return np.concatenate([tail * (1 - ramp) + head * ramp, body])


# --- Guns ---------------------------------------------------------------

def gunshot(seconds, crack_decay, thump_hz, thump_decay, tail, bright):
    crack = highpass(noise(seconds), bright) * env(seconds, 0.0005, crack_decay)
    body = band(noise(seconds), 150, 2500) * env(seconds, 0.001, crack_decay * 3)
    t = t_axis(seconds)
    thump = np.sin(2 * np.pi * thump_hz * t * (1 - 0.4 * t / seconds)) * env(seconds, 0.001, thump_decay)
    x = crack * 0.9 + body * 0.8 + thump * 1.2
    return echo(x, 0.09, tail, taps=4)


def guns():
    for i in range(3):
        save(f"pistol_{i}", gunshot(0.6, 0.012 + i * 0.002, 140 + i * 15, 0.05, 0.25, 1800))
        save(f"mg_{i}", gunshot(0.35, 0.01, 120 + i * 10, 0.04, 0.15, 1500))
        save(f"guard_gun_{i}", gunshot(0.5, 0.01, 170 + i * 12, 0.04, 0.2, 2200))
    for i in range(2):
        save(f"shotgun_{i}", gunshot(0.9, 0.025, 85 + i * 8, 0.12, 0.35, 900))
        save(f"rifle_{i}", gunshot(1.2, 0.008, 110 + i * 10, 0.08, 0.45, 2500))


def whoosh(seconds, start_hz, end_hz, rough=0.0):
    x = noise(seconds)
    out = np.zeros_like(x)
    chunk = 512
    for j in range(0, len(x), chunk):
        f = start_hz + (end_hz - start_hz) * j / len(x)
        out[j:j + chunk] = band(x[max(0, j - 2048):j + chunk], f * 0.7, f * 1.3)[-len(x[j:j + chunk]):]
    e = np.sin(np.pi * np.clip(t_axis(seconds) / seconds, 0, 1)) ** 1.5
    return out * e + rough * noise(seconds) * e * 0.2


def throws():
    for i in range(2):
        save(f"throw_{i}", whoosh(0.35, 500 + i * 150, 1600))
    launch = whoosh(1.0, 300, 2400, rough=1.0) + gunshot(1.0, 0.02, 70, 0.15, 0.3, 600) * 0.8
    save("rocket_0", launch)


# --- Explosions ----------------------------------------------------------

def boom(seconds, low, decay, crack):
    rumble = lowpass(noise(seconds), low, order=4) * env(seconds, 0.004, decay)
    t = t_axis(seconds)
    sub = np.sin(2 * np.pi * 45 * t * (1 - 0.5 * t / seconds)) * env(seconds, 0.002, decay * 0.6)
    snap = highpass(noise(seconds), 1200) * env(seconds, 0.0005, 0.03) * crack
    debris = band(noise(seconds), 2000, 6000) * env(seconds, 0.2, decay * 0.8) * 0.15
    return echo(rumble * 1.6 + sub * 1.4 + snap + debris, 0.14, 0.3, taps=3)


def explosions():
    for i in range(3):
        save(f"explosion_{i}", boom(2.8, 380 + i * 120, 0.55 + i * 0.12, 0.8))
    save("explosion_big_0", boom(4.0, 260, 1.1, 1.0))
    save("shockwave_0", boom(2.0, 180, 0.5, 0.2) + whoosh(2.0, 200, 60) * 0.6)


# --- Loops ---------------------------------------------------------------

def engine_loop(fundamental, seconds=2.0, grit=0.3):
    t = t_axis(seconds)
    f = round(fundamental * seconds) / seconds  # whole cycles: seamless loop
    x = np.zeros_like(t)
    for h, a in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.25), (6, 0.12)]:
        x += a * np.sin(2 * np.pi * f * h * t + rng.uniform(0, np.pi))
    pulses = (np.sin(2 * np.pi * f * 0.5 * t) > 0.6) * 0.3
    x = x * (0.8 + pulses) + grit * lowpass(noise(seconds), 800)
    return loopable(lowpass(x, 1800), 0.2)


def loops():
    save("engine_loop_0", engine_loop(38))
    save("dozer_loop_0", engine_loop(24, grit=0.6))
    t = t_axis(2.0)
    whine = np.sin(2 * np.pi * 330 * t) * 0.6 + np.sin(2 * np.pi * 660 * t) * 0.25 + np.sin(2 * np.pi * 991 * t) * 0.1
    save("ev_loop_0", loopable(whine + 0.25 * band(noise(2.0), 400, 3000), 0.2))
    roar = lowpass(noise(3.0), 900, order=3) * 1.2 + band(noise(3.0), 1500, 4500) * 0.35
    roar += 0.25 * np.sin(2 * np.pi * 1180 * t_axis(3.0)) + 0.15 * np.sin(2 * np.pi * 2360 * t_axis(3.0))
    save("turbine_loop_0", loopable(roar, 0.4))
    crackle = band(noise(3.0), 300, 5000) * 0.25
    pops = np.zeros(int(RATE * 3.0))
    for _ in range(60):
        at = rng.integers(0, len(pops) - 800)
        pops[at:at + 800] += band(noise(800 / RATE), 1500, 7000) * np.exp(-np.arange(800) / 90) * rng.uniform(0.3, 1.0)
    save("fire_loop_0", loopable(crackle + pops + lowpass(noise(3.0), 200) * 0.6, 0.3))
    save("hiss_loop_0", loopable(band(noise(2.0), 2500, 9000, 3) + lowpass(noise(2.0), 600) * 0.3, 0.3))
    # Birdsong: random chirps and trills over 12 s.
    seconds = 12.0
    birds = np.zeros(int(RATE * seconds))
    for _ in range(38):
        start = rng.uniform(0.2, seconds - 1.2)
        base = rng.uniform(2200, 4800)
        notes = rng.integers(1, 6)
        for k in range(notes):
            d = rng.uniform(0.05, 0.14)
            tt = t_axis(d)
            sweep = base * (1 + rng.uniform(-0.25, 0.35) * tt / d)
            chirp = np.sin(2 * np.pi * np.cumsum(sweep) / RATE) * np.sin(np.pi * tt / d) ** 2
            at = int(RATE * (start + k * (d + 0.03)))
            birds[at:at + len(chirp)] += chirp * rng.uniform(0.2, 0.7)
    save("birds_loop_0", loopable(birds + lowpass(noise(seconds), 300) * 0.02, 0.5), peak=0.6)


# --- Critters and voices -------------------------------------------------

def bark(pitch):
    seconds = 0.22
    t = t_axis(seconds)
    f = pitch * (1.3 - 0.6 * t / seconds)
    tone = signal.sawtooth(2 * np.pi * np.cumsum(f) / RATE)
    x = band(tone, 350, 2200) + band(noise(seconds), 600, 3000) * 0.5
    return x * env(seconds, 0.01, 0.06)


def barks():
    for i in range(3):
        one = bark(260 + i * 40)
        two = bark(240 + i * 40)
        save(f"bark_{i}", np.concatenate([one, np.zeros(int(RATE * 0.08)), two * 0.8]))
    whimper = np.sin(2 * np.pi * np.cumsum(900 + 300 * np.sin(np.linspace(0, 3, int(RATE * 0.5)))) / RATE)
    save("whimper_0", whimper * env(0.5, 0.05, 0.2) * 0.8)


def babble(syllables, base):
    """Robotic corporate gibberish: formant-filtered pulse syllables."""
    out = []
    for _ in range(syllables):
        d = rng.uniform(0.08, 0.18)
        t = t_axis(d)
        f0 = base * rng.uniform(0.85, 1.2)
        src = signal.square(2 * np.pi * f0 * t, duty=0.3)
        f1, f2 = rng.choice([(700, 1200), (400, 2000), (300, 900), (600, 1700), (500, 1500)])
        syl = band(src, f1 * 0.8, f1 * 1.2) + 0.6 * band(src, f2 * 0.85, f2 * 1.15)
        out.append(syl * np.sin(np.pi * t / d) ** 0.7)
        out.append(np.zeros(int(RATE * rng.uniform(0.01, 0.05))))
    return np.concatenate(out)


def voices():
    for i in range(4):
        save(f"babble_{i}", babble(int(rng.integers(5, 9)), 140))


def alarm():
    """Two-tone site siren, about 2.4 s."""
    seconds = 2.4
    t = t_axis(seconds)
    f = np.where((t * 2.5).astype(int) % 2 == 0, 880.0, 660.0)
    tone = signal.square(2 * np.pi * np.cumsum(f) / RATE, duty=0.5) * 0.5 + np.sin(2 * np.pi * np.cumsum(f) / RATE) * 0.5
    save("alarm_0", lowpass(tone, 3500) * np.clip(t / 0.05, 0, 1) * np.clip((seconds - t) / 0.2, 0, 1))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kenney", type=Path, help="folder holding the unzipped kenney_* packs")
    args = parser.parse_args()
    guns()
    throws()
    explosions()
    loops()
    barks()
    voices()
    alarm()
    if args.kenney:
        copy_kenney(args.kenney)
    print(f"wrote {len(list(OUT.glob('*.*')))} files to {OUT}")


# cue -> list of source file names (searched recursively in --kenney).
KENNEY = {
    "step_concrete": [f"footstep_concrete_00{i}.ogg" for i in range(5)],
    "step_grass": [f"footstep_grass_00{i}.ogg" for i in range(5)],
    "hit_metal": [f"impactMetal_light_00{i}.ogg" for i in range(5)],
    "hit_flesh": [f"impactPunch_medium_00{i}.ogg" for i in range(5)],
    "hit_soft": [f"impactSoft_medium_00{i}.ogg" for i in range(5)],
    "hit_wood": [f"impactPlank_medium_00{i}.ogg" for i in range(5)],
    "break_heavy": [f"impactPlate_heavy_00{i}.ogg" for i in range(5)],
    "break_rock": [f"impactMining_00{i}.ogg" for i in range(5)],
    "glass_break": [f"impactGlass_heavy_00{i}.ogg" for i in range(5)],
    "car_crash": [f"impactMetal_heavy_00{i}.ogg" for i in range(5)],
    "bottle": [f"impactGlass_light_00{i}.ogg" for i in range(3)],
    "laser": [f"laserSmall_00{i}.ogg" for i in range(5)],
    "zap": [f"forceField_00{i}.ogg" for i in range(5)],
    "emp": ["lowFrequency_explosion_000.ogg", "lowFrequency_explosion_001.ogg"],
    "crunch": [f"explosionCrunch_00{i}.ogg" for i in range(5)],
    "computer": [f"computerNoise_00{i}.ogg" for i in range(4)],
    "door_open": [f"doorOpen_00{i}.ogg" for i in range(3)],
    "unlock": ["confirmation_002.ogg"],
    "click": ["click_002.ogg", "click_003.ogg"],
    "hover": ["tick_002.ogg"],
    "back": ["back_002.ogg"],
    "open": ["open_001.ogg"],
    "close": ["close_001.ogg"],
    "confirm": ["confirmation_001.ogg"],
    "error": ["error_004.ogg"],
    "cash": ["select_006.ogg"],
    "tip": ["question_001.ogg"],
    "beep": ["tick_001.ogg"],
    "place": ["drop_002.ogg"],
    "glitch": [f"glitch_00{i}.ogg" for i in range(1, 5)],
    "jingle_wave": ["jingles_HIT00.ogg"],
    "jingle_clear": ["jingles_NES03.ogg"],
    "jingle_boss": ["jingles_HIT05.ogg"],
    "jingle_win": ["jingles_SAX07.ogg"],
    "jingle_lose": ["jingles_PIZZI10.ogg"],
    "jingle_deed": ["jingles_NES00.ogg"],
}


def copy_kenney(root):
    index = {p.name: p for p in root.rglob("*.ogg")}
    for cue, names in KENNEY.items():
        for n, name in enumerate(names):
            if name not in index:
                raise SystemExit(f"missing Kenney file {name} for cue {cue}")
            shutil.copyfile(index[name], OUT / f"{cue}_{n}.ogg")


if __name__ == "__main__":
    main()
