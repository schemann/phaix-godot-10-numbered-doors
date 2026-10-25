#!/usr/bin/env python3
"""Writes every sound of the tutorial into res://sounds, from nothing but numbers.

There are no recorded or downloaded sounds in this project: each WAV is synthesized here, with Python's
standard library only (wave, math, random with a fixed seed per sound), so running the script again gives
the same files byte for byte. The sounds are MIT licensed like the code.

  footstep_stone_1..4.wav  a step on the stone floor, four variants: a soft heel thud and the grit of
                           the sole (a noise burst through a band-pass filter, with an envelope), then
                           the toe a moment later
  door_open.wav            the latch clicks, the hinge creaks while the door swings, a soft bump as it stops
  door_close.wav           a short creak, then the thud of the door in its frame and the latch
  lock_rattle.wav          three metal clanks, each weaker than the one before (the door's three pushes)
  key_chime.wav            two bell notes, a fifth apart
  room_tone.wav            four seconds of a quiet room: low rumble and a little air, a seamless loop

All files: 48 kHz (the rate Godot's Movie Maker records at), 16 bit, mono. Every sound but the loop gets
2 ms fades at both ends, so nothing clicks. The loop is rendered on a circular buffer: its filters run
twice round the buffer and the second lap is kept, so the end flows into the start without a seam.

Usage (from the project folder):
  python3 tools/sfx/make_sfx.py            writes sounds/*.wav and prints what it wrote
  python3 tools/sfx/make_sfx.py --out=DIR  writes into DIR instead
  python3 tools/sfx/make_sfx.py --check    writes nothing; exit 1 if a file in sounds/ is not what the
                                           script makes (byte for byte)
"""
import io
import math
import os
import random
import struct
import sys
import wave

RATE = 48000
PEAKS = {  # the loudest sample of each file, in dB below full scale (the players set the mix)
    "footstep": -9.0,
    "door_open": -4.0,
    "door_close": -3.0,
    "lock_rattle": -3.0,
    "key_chime": -4.0,
    "room_tone": -20.0,
}


def silence(seconds):
    return [0.0] * int(round(seconds * RATE))


def add(target, sound, at_seconds, gain=1.0):
    """Mixes sound into target, starting at at_seconds."""
    start = int(round(at_seconds * RATE))
    for i, value in enumerate(sound):
        if start + i < len(target):
            target[start + i] += value * gain


def noise(rng, seconds):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(round(seconds * RATE)))]


def low_pass(samples, cutoff, state=0.0):
    """One-pole low-pass filter. Returns the filtered samples and the filter's last value."""
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    out = []
    y = state
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out, y


def high_pass(samples, cutoff):
    low, _ = low_pass(samples, cutoff)
    return [x - y for x, y in zip(samples, low)]


def band_pass(samples, centre, q):
    """A resonant band-pass filter (the biquad of the Audio EQ Cookbook, 0 dB peak gain)."""
    w = 2.0 * math.pi * centre / RATE
    alpha = math.sin(w) / (2.0 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1.0 + alpha, -2.0 * math.cos(w), 1.0 - alpha
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in samples:
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x
        y2, y1 = y1, y
        out.append(y)
    return out


def envelope(samples, attack, decay):
    """A fast linear attack, then an exponential decay with the time constant `decay` (seconds)."""
    out = []
    for i, x in enumerate(samples):
        t = i / RATE
        rise = min(1.0, t / attack) if attack > 0.0 else 1.0
        out.append(x * rise * math.exp(-t / decay))
    return out


def tone(frequency, seconds, decay, attack=0.002, drop=0.0):
    """A decaying sine. drop: how far the pitch falls over the first 50 ms, as a fraction (a thud)."""
    out = []
    phase = 0.0
    for i in range(int(round(seconds * RATE))):
        t = i / RATE
        f = frequency * (1.0 - drop * min(1.0, t / 0.05))
        phase += 2.0 * math.pi * f / RATE
        rise = min(1.0, t / attack)
        out.append(math.sin(phase) * rise * math.exp(-t / decay))
    return out


def partials(base, ratios, amplitudes, decays, seconds, attack=0.002):
    """A struck object: sines at ratios of the base frequency, each with its own level and decay."""
    out = silence(seconds)
    for ratio, amplitude, decay in zip(ratios, amplitudes, decays):
        add(out, tone(base * ratio, seconds, decay, attack), 0.0, amplitude)
    return out


def fade_ends(samples, seconds=0.002):
    n = int(round(seconds * RATE))
    for i in range(min(n, len(samples))):
        samples[i] *= i / n
        samples[-1 - i] *= i / n
    return samples


def normalize(samples, peak_db):
    peak = max(abs(x) for x in samples)
    gain = 10.0 ** (peak_db / 20.0) / peak
    return [x * gain for x in samples]


# --- the sounds ------------------------------------------------------------------------------------

def footstep(variant):
    """Heel and toe: a low thud with the grit of the sole on stone, the toe 50 to 65 ms later."""
    rng = random.Random(1000 + variant)
    length = 0.24
    out = silence(length)
    thud = tone(78.0 + 6.0 * variant, length, 0.022, attack=0.001, drop=0.3)
    add(out, thud, 0.0, 0.55)
    grit_centre = 1500.0 + 260.0 * variant + rng.uniform(-80.0, 80.0)
    heel = envelope(band_pass(noise(rng, length), grit_centre, 0.9), 0.002, 0.030 + 0.004 * variant)
    add(out, heel, 0.0, 1.0)
    toe_at = 0.045 + 0.005 * variant
    toe = envelope(band_pass(noise(rng, length - toe_at), grit_centre * 1.3, 1.1), 0.0015, 0.018)
    add(out, toe, toe_at, 0.45)
    return out


def creak(rng, seconds, start_hz, end_hz, jitter):
    """A hinge: stick-slip, a train of little clicks whose rate glides from start_hz to end_hz, unevenly,
    ringing the wood at two resonances."""
    pulses = silence(seconds)
    t = 0.0
    while t < seconds:
        index = int(t * RATE)
        if index >= len(pulses):
            break
        progress = t / seconds
        pulses[index] += rng.uniform(0.6, 1.0) * (1.0 if rng.random() > 0.1 else -1.0)
        rate = start_hz + (end_hz - start_hz) * progress
        t += (1.0 / rate) * (1.0 + rng.uniform(-jitter, jitter))
    body = band_pass(pulses, 620.0, 7.0)
    upper = band_pass(pulses, 1480.0, 9.0)
    sound = [a + 0.6 * b for a, b in zip(body, upper)]
    # Swell in over 60 ms, fade out over the last 120 ms.
    n = len(sound)
    for i in range(n):
        tt = i / RATE
        sound[i] *= min(1.0, tt / 0.06) * min(1.0, (seconds - tt) / 0.12)
    return normalize(sound, 0.0)


def latch(rng, gain=1.0):
    click = envelope(high_pass(noise(rng, 0.05), 2000.0), 0.0005, 0.004)
    ping = tone(2350.0, 0.08, 0.015, attack=0.0005)
    out = silence(0.08)
    add(out, click, 0.0, 1.0 * gain)
    add(out, ping, 0.0, 0.25 * gain)
    return out


def thud(rng, seconds, frequency, decay):
    out = silence(seconds)
    add(out, tone(frequency, seconds, decay, attack=0.001, drop=0.25), 0.0, 1.0)
    body, _ = low_pass(noise(rng, seconds), 400.0)
    add(out, envelope(body, 0.001, decay * 0.8), 0.0, 2.5)
    return normalize(out, 0.0)


def door_open():
    """The latch, the creak while the door swings (0.5 s), a soft bump where it stops."""
    rng = random.Random(2001)
    out = silence(0.8)
    add(out, latch(rng), 0.0, 0.5)
    add(out, creak(rng, 0.5, 105.0, 70.0, 0.12), 0.04, 0.8)
    add(out, thud(rng, 0.25, 70.0, 0.04), 0.52, 0.3)
    return out


def door_close():
    """A short, higher creak while it swings back, then the thud in the frame (at 0.5 s) and the latch."""
    rng = random.Random(2002)
    out = silence(0.95)
    add(out, creak(rng, 0.42, 120.0, 95.0, 0.1), 0.0, 0.45)
    add(out, thud(rng, 0.4, 62.0, 0.07), 0.5, 1.0)
    add(out, latch(rng), 0.505, 0.4)
    return out


def lock_rattle():
    """Three clanks of the lock against the bar, 90 ms apart (the door's three pushes), each weaker."""
    rng = random.Random(3001)
    out = silence(0.5)
    for i, strength in enumerate([1.0, 0.65, 0.35]):
        base = 410.0 * (1.0 + rng.uniform(-0.02, 0.02))
        clank = partials(base, [1.0, 2.76, 5.40, 8.93], [1.0, 0.6, 0.35, 0.2], [0.09, 0.06, 0.035, 0.02], 0.3, attack=0.0005)
        click = envelope(high_pass(noise(rng, 0.03), 3000.0), 0.0003, 0.003)
        bolt = envelope(band_pass(noise(rng, 0.06), 3100.0, 2.0), 0.001, 0.015)
        at = 0.09 * i
        add(out, clank, at, strength)
        add(out, click, at, 0.8 * strength)
        add(out, bolt, at + 0.012, 0.6 * strength)
    return out


def key_chime():
    """Two soft bell notes, E6 then B6, 90 ms apart."""
    out = silence(1.1)
    for at, frequency, gain in [(0.0, 1318.5, 1.0), (0.09, 1975.5, 0.8)]:
        bell = partials(frequency, [1.0, 2.0, 3.01, 4.2], [1.0, 0.35, 0.18, 0.08], [0.45, 0.25, 0.15, 0.08], 1.1 - at, attack=0.003)
        add(out, bell, at, gain)
    return out


def room_tone():
    """Four seconds of a quiet room, made to loop: low rumble, a little air, a slow breath in the level.
    The filters run twice round the buffer and the second lap is kept, so their state at the end is the
    state at the start; the breath is one whole cycle per loop."""
    rng = random.Random(4001)
    seconds = 4.0
    n = int(seconds * RATE)
    raw = noise(rng, seconds)
    air_raw = noise(rng, seconds)
    _, rumble_state = low_pass(raw, 180.0)
    rumble, _ = low_pass(raw, 180.0, rumble_state)
    _, deep_state = low_pass(rumble, 60.0)
    deep, _ = low_pass(rumble, 60.0, deep_state)
    _, air_state = low_pass(air_raw, 2500.0)
    air_low, _ = low_pass(air_raw, 2500.0, air_state)
    _, under_state = low_pass(air_low, 600.0)
    under, _ = low_pass(air_low, 600.0, under_state)
    air = [a - b for a, b in zip(air_low, under)]  # 600 to 2500 Hz, a soft hiss
    out = []
    for i in range(n):
        breath = 1.0 + 0.12 * math.sin(2.0 * math.pi * i / n)
        out.append((rumble[i] * 1.0 + deep[i] * 2.0 + air[i] * 0.05) * breath)
    return out


SOUNDS = [
    ("footstep_stone_1.wav", lambda: footstep(1), "footstep"),
    ("footstep_stone_2.wav", lambda: footstep(2), "footstep"),
    ("footstep_stone_3.wav", lambda: footstep(3), "footstep"),
    ("footstep_stone_4.wav", lambda: footstep(4), "footstep"),
    ("door_open.wav", door_open, "door_open"),
    ("door_close.wav", door_close, "door_close"),
    ("lock_rattle.wav", lock_rattle, "lock_rattle"),
    ("key_chime.wav", key_chime, "key_chime"),
    ("room_tone.wav", room_tone, "room_tone"),
]


def wav_bytes(samples):
    frames = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(x * 32767.0))))) for x in samples)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(frames)
    return buffer.getvalue()


def render(name, make, kind):
    samples = make()
    if kind != "room_tone":  # a loop must not fade: its end runs into its start
        samples = fade_ends(samples)
    samples = normalize(samples, PEAKS[kind])
    return wav_bytes(samples), samples


def main():
    project = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out_dir = os.path.join(project, "sounds")
    check = False
    for argument in sys.argv[1:]:
        if argument.startswith("--out="):
            out_dir = os.path.abspath(argument[len("--out="):])
        elif argument == "--check":
            check = True
        else:
            sys.exit("unknown argument: %s" % argument)
    if not check:
        os.makedirs(out_dir, exist_ok=True)
    differs = []
    for name, make, kind in SOUNDS:
        data, samples = render(name, make, kind)
        path = os.path.join(out_dir, name)
        peak = 20.0 * math.log10(max(abs(x) for x in samples))
        rms = 20.0 * math.log10(math.sqrt(sum(x * x for x in samples) / len(samples)))
        if check:
            same = os.path.isfile(path) and open(path, "rb").read() == data
            if not same:
                differs.append(name)
            print("%-22s %s" % (name, "same" if same else "DIFFERS"))
        else:
            with open(path, "wb") as file:
                file.write(data)
            print("%-22s %5.2f s  peak %6.1f dBFS  rms %6.1f dBFS" % (name, len(samples) / RATE, peak, rms))
    if check:
        print("SFX %s" % ("OK: every file is what the script makes" if not differs else "DIFFERS: " + ", ".join(differs)))
        sys.exit(1 if differs else 0)


if __name__ == "__main__":
    main()
