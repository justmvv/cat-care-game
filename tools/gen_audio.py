#!/usr/bin/env python3
"""Generates all game audio (SFX + music) as 16-bit mono WAV files.

Music: a synthesized ragtime arrangement inspired by Zez Confrey's
"Kitten on the Keys" (1921, public domain).

Usage: python3 gen_audio.py [output_dir]
"""
import math
import os
import random
import struct
import sys
import wave

SR = 22050

def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))

def write_wav(path, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = gain / peak
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(
            struct.pack('<h', int(clamp(s * norm) * 32767)) for s in samples))
    print('wrote', path, f'{len(samples)/SR:.2f}s')

def silence(dur):
    return [0.0] * int(SR * dur)

def mix_into(dst, src, offset_sec, vol=1.0):
    off = int(offset_sec * SR)
    need = off + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, s in enumerate(src):
        dst[off + i] += s * vol

def env_adsr(n, a=0.02, d=0.08, s=0.6, r=0.15):
    out = []
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    ns = max(0, n - na - nd - nr)
    for i in range(n):
        if i < na:
            out.append(i / max(1, na))
        elif i < na + nd:
            t = (i - na) / max(1, nd)
            out.append(1 - t * (1 - s))
        elif i < na + nd + ns:
            out.append(s)
        else:
            t = (i - na - nd - ns) / max(1, nr)
            out.append(s * (1 - t))
    return out

# ---------------------------------------------------------------- SFX

def meow(base=430, top=760, dur=0.7, vib=6.5, breathy=0.12, seed=1):
    rnd = random.Random(seed)
    n = int(dur * SR)
    env = env_adsr(n, a=0.06, d=0.1, s=0.75, r=0.28)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        # pitch: rise then fall, like "mee-ow"
        if t < 0.45:
            f = base + (top - base) * (t / 0.45)
        else:
            f = top - (top - base * 0.85) * ((t - 0.45) / 0.55)
        f *= 1 + 0.03 * math.sin(2 * math.pi * vib * i / SR)
        phase += 2 * math.pi * f / SR
        # formant-ish: fundamental + strong 2nd/3rd harmonics
        v = (math.sin(phase) + 0.55 * math.sin(2 * phase + 0.3)
             + 0.3 * math.sin(3 * phase) + 0.12 * math.sin(4 * phase))
        v += breathy * (rnd.random() * 2 - 1)
        out.append(v * env[i])
    return out

def purr(dur=1.6):
    rnd = random.Random(7)
    n = int(dur * SR)
    env = env_adsr(n, a=0.2, d=0.2, s=0.8, r=0.4)
    out, ph = [], 0.0
    for i in range(n):
        # 24 Hz rumble amplitude-modulating a low tone + soft noise
        am = 0.55 + 0.45 * math.sin(2 * math.pi * 24 * i / SR)
        ph += 2 * math.pi * 85 / SR
        v = (0.7 * math.sin(ph) + 0.5 * (rnd.random() * 2 - 1)) * am
        out.append(v * env[i])
    # simple lowpass
    f, prev = [], 0.0
    for v in out:
        prev += 0.25 * (v - prev)
        f.append(prev)
    return f

def noise_burst(dur, lp=0.3, seed=3):
    rnd = random.Random(seed)
    n = int(dur * SR)
    out, prev = [], 0.0
    for i in range(n):
        prev += lp * ((rnd.random() * 2 - 1) - prev)
        out.append(prev * (1 - i / n) ** 2)
    return out

def scratch():
    out = silence(0.9)
    for k in range(3):
        rip = noise_burst(0.16, lp=0.55, seed=10 + k)
        mix_into(out, rip, 0.05 + k * 0.28, vol=1.0 - k * 0.15)
    return out

def crash():
    out = silence(1.0)
    mix_into(out, noise_burst(0.35, lp=0.8, seed=42), 0.0, 1.0)
    rnd = random.Random(5)
    for _ in range(9):  # glassy shards
        f0 = rnd.uniform(1400, 4200)
        dur = rnd.uniform(0.15, 0.5)
        n = int(dur * SR)
        tone = [math.sin(2 * math.pi * f0 * i / SR) * math.exp(-6 * i / n)
                for i in range(n)]
        mix_into(out, tone, rnd.uniform(0.0, 0.25), 0.25)
    return out

def munch():
    out = silence(1.0)
    for k in range(5):
        b = noise_burst(0.09, lp=0.35, seed=20 + k)
        mix_into(out, b, 0.05 + k * 0.18, 0.9)
    return out

def scoop():
    out = silence(0.8)
    for k in range(2):
        b = noise_burst(0.3, lp=0.18, seed=30 + k)
        mix_into(out, b, k * 0.35, 0.9)
    return out

def bell_tone(f0, dur, vol=1.0):
    n = int(dur * SR)
    return [vol * math.exp(-4.5 * i / n) *
            (math.sin(2 * math.pi * f0 * i / SR)
             + 0.6 * math.sin(2 * math.pi * f0 * 2.76 * i / SR)
             + 0.3 * math.sin(2 * math.pi * f0 * 5.4 * i / SR))
            for i in range(n)]

def jingle():
    out = silence(0.9)
    for k, f in enumerate([2100, 2400, 2100]):
        mix_into(out, bell_tone(f, 0.4), k * 0.18, 0.8)
    return out

def doorbell():
    out = silence(1.4)
    mix_into(out, bell_tone(659.3, 0.8), 0.0, 1.0)   # E5
    mix_into(out, bell_tone(523.3, 0.9), 0.45, 1.0)  # C5
    return out

def piano_note(f0, dur, vol=1.0):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        e = math.exp(-3.2 * i / n)
        v = (math.sin(2 * math.pi * f0 * t)
             + 0.5 * math.sin(2 * math.pi * f0 * 2 * t)
             + 0.25 * math.sin(2 * math.pi * f0 * 3 * t)
             + 0.12 * math.sin(2 * math.pi * f0 * 4 * t))
        out.append(v * e * vol)
    return out

def success():
    out = silence(1.3)
    for k, m in enumerate([60, 64, 67, 72]):  # C E G C
        f = 440 * 2 ** ((m - 69) / 12)
        mix_into(out, piano_note(f, 0.55), k * 0.12, 0.8)
    return out

def fail():
    out = silence(1.2)
    for k, m in enumerate([62, 58]):  # D -> Bb, sad
        f = 440 * 2 ** ((m - 69) / 12)
        mix_into(out, piano_note(f, 0.7), k * 0.35, 0.9)
    return out

def pop():
    n = int(0.09 * SR)
    return [math.sin(2 * math.pi * (900 - 500 * i / n) * i / SR)
            * (1 - i / n) for i in range(n)]

def chirp():  # bird outside the window
    out = silence(0.9)
    rnd = random.Random(11)
    t0 = 0.0
    for _ in range(4):
        f0 = rnd.uniform(2800, 3600)
        n = int(0.11 * SR)
        tw = [math.sin(2 * math.pi * (f0 + 900 * math.sin(math.pi * i / n))
                       * i / SR) * math.sin(math.pi * i / n) for i in range(n)]
        mix_into(out, tw, t0, 0.8)
        t0 += rnd.uniform(0.15, 0.24)
    return out

def thunder():
    rnd = random.Random(99)
    n = int(2.4 * SR)
    out = []
    prev = 0.0
    for i in range(n):
        t_ = i / n
        # sharp crack at the start, then a long low rumble
        crack = (rnd.random() * 2 - 1) * max(0.0, 1 - t_ * 22)
        prev += 0.06 * ((rnd.random() * 2 - 1) - prev)  # heavy lowpass
        rumble = prev * (1 - t_) ** 1.4 * (1 + 0.5 * math.sin(2 * math.pi * 2.1 * t_ * 2.4))
        out.append(crack * 0.7 + rumble * 2.2)
    return out

def buzz():
    n = int(1.0 * SR)
    out = []
    for i in range(n):
        ts = i / SR
        f = 175 + 22 * math.sin(2 * math.pi * 2.8 * ts)
        am = 0.6 + 0.4 * math.sin(2 * math.pi * 24 * ts)
        v = (math.sin(2 * math.pi * f * ts)
             + 0.45 * math.sin(2 * math.pi * f * 2 * ts)
             + 0.25 * math.sin(2 * math.pi * f * 3 * ts)) * am
        env = min(1.0, i / (0.08 * SR)) * min(1.0, (n - i) / (0.2 * SR))
        out.append(v * env)
    return out

# ------------------------------------------------------------- MUSIC
# Ragtime arrangement inspired by "Kitten on the Keys" (Zez Confrey,
# 1921 — public domain). Melody simplified/approximated.

NOTE = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,'F#':6,'Gb':6,
        'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11}

def midi(name):
    # e.g. 'Eb4'
    pitch = name[:-1]
    octave = int(name[-1])
    return 12 * (octave + 1) + NOTE[pitch]

def freq(m):
    return 440 * 2 ** ((m - 69) / 12)

def music():
    bpm = 190          # eighth-note pulse of a brisk rag
    beat = 60 / bpm    # one eighth note
    out = silence(1)

    def note(name, start_e, len_e, vol=0.5):
        mix_into(out, piano_note(freq(midi(name)), len_e * beat * 1.05, 1.0),
                 start_e * beat, vol)

    def chord(names, start_e, len_e, vol=0.4):
        for nm in names:
            note(nm, start_e, len_e, vol / max(1, len(names) - 1))

    # --- stride bass in Eb: root on 1&3, chord on 2&4 (per quarter = 2 eighths)
    def stride(bar_e, roots, chords):
        # roots: two bass notes, chords: chord names list
        note(roots[0], bar_e + 0, 2, 0.55)
        chord(chords, bar_e + 2, 2, 0.5)
        note(roots[1], bar_e + 4, 2, 0.55)
        chord(chords, bar_e + 6, 2, 0.5)

    EB = (['Eb2', 'Bb2'], ['G3', 'Bb3', 'Eb4'])
    AB = (['Ab2', 'Eb3'], ['Ab3', 'C4', 'Eb4'])
    BB7 = (['Bb2', 'F3'], ['Ab3', 'Bb3', 'D4'])
    F7 = (['F2', 'C3'], ['F3', 'A3', 'Eb4'])

    bass_plan = [EB, EB, AB, EB, EB, F7, BB7, EB,
                 EB, EB, AB, EB, EB, BB7, EB, EB]
    for b, (r, c) in enumerate(bass_plan):
        stride(b * 8, r, c)

    # --- melody: perky syncopated line with chromatic "kitten runs"
    v = 0.85
    def run(names, start_e, step=1, ln=1, vol=v):
        for i, nm in enumerate(names):
            note(nm, start_e + i * step, ln, vol)

    # A phrase (bars 1-4): chromatic scamper up, syncopated hook
    run(['G4', 'Ab4', 'A4', 'Bb4'], 0, 1, 1)
    note('C5', 4, 1); note('Bb4', 5, 1); note('G4', 6, 2)
    run(['Eb5', 'D5', 'Db5', 'C5'], 8, 1, 1)
    note('Bb4', 12, 2); note('G4', 14, 2)
    run(['C5', 'B4', 'C5', 'Eb5'], 16, 1, 1)
    note('C5', 20, 1); note('Ab4', 21, 1); note('Eb4', 22, 2)
    run(['G4', 'Ab4', 'A4', 'Bb4'], 24, 1, 1)
    note('G4', 28, 1.5); note('Eb4', 30, 2)

    # B phrase (bars 5-8): answer, cadence on Bb7 -> Eb
    run(['F4', 'G4', 'Ab4', 'A4'], 32, 1, 1)
    note('Bb4', 36, 2); note('D5', 38, 2)
    note('C5', 40, 1); note('Bb4', 41, 1); note('Ab4', 42, 1); note('G4', 43, 1)
    note('F4', 44, 2); note('Bb4', 46, 2)
    run(['Eb5', 'D5', 'C5', 'Bb4'], 48, 1, 1)
    note('G4', 52, 2); note('Bb4', 54, 2)
    note('Eb5', 56, 3); note('Bb4', 59, 1); note('G4', 60, 2); note('Eb4', 62, 2)

    # A' phrase (bars 9-12): octave-up scamper
    run(['G5', 'Ab5', 'A5', 'Bb5'], 64, 1, 1, 0.7)
    note('C6', 68, 1, 0.7); note('Bb5', 69, 1, 0.7); note('G5', 70, 2, 0.7)
    run(['Eb5', 'E5', 'F5', 'Gb5'], 72, 1, 1)
    note('G5', 76, 2); note('Eb5', 78, 2)
    run(['C5', 'Db5', 'D5', 'Eb5'], 80, 1, 1)
    note('C5', 84, 1); note('Ab4', 85, 1); note('Eb4', 86, 2)
    run(['G4', 'Bb4', 'C5', 'Eb5'], 88, 1, 1)
    note('D5', 92, 2); note('Bb4', 94, 2)

    # final phrase (bars 13-16): big finish
    note('C5', 96, 1); note('Eb5', 97, 1); note('D5', 98, 1); note('F5', 99, 1)
    note('Eb5', 100, 2); note('Bb4', 102, 2)
    run(['Eb5', 'D5', 'Db5', 'C5', 'B4', 'C5'], 104, 1, 1)
    note('Bb4', 110, 2)
    run(['G4', 'Ab4', 'A4', 'Bb4', 'B4', 'C5'], 112, 1, 1)
    note('Eb5', 118, 2)
    chord(['G4', 'Bb4', 'Eb5'], 120, 4, 0.9)
    chord(['Eb4', 'G4', 'Bb4', 'Eb5'], 124, 4, 1.0)

    return out

# Ragtime arrangement inspired by "The Entertainer" (Scott Joplin,
# 1902 — public domain). Melody simplified/approximated.
def entertainer():
    bpm = 185
    beat = 60 / bpm  # one eighth note
    out = silence(1)

    def note(name, start_e, len_e, vol=0.5):
        mix_into(out, piano_note(freq(midi(name)), len_e * beat * 1.05, 1.0),
                 start_e * beat, vol)

    def chord(names, start_e, len_e, vol=0.4):
        for nm in names:
            note(nm, start_e, len_e, vol / max(1, len(names) - 1))

    def stride(bar_e, roots, chords):
        note(roots[0], bar_e + 0, 2, 0.55)
        chord(chords, bar_e + 2, 2, 0.5)
        note(roots[1], bar_e + 4, 2, 0.55)
        chord(chords, bar_e + 6, 2, 0.5)

    C = (['C2', 'G2'], ['E3', 'G3', 'C4'])
    G7 = (['G2', 'D3'], ['F3', 'G3', 'B3'])
    F = (['F2', 'C3'], ['F3', 'A3', 'C4'])
    A7 = (['A2', 'E3'], ['G3', 'A3', 'Db4'])

    bass_plan = [C, C, G7, C, C, C, G7, C,
                 C, C7 := (['C2', 'G2'], ['E3', 'Bb3', 'C4']), F, C, G7, G7, C, C]
    for b, (r, c) in enumerate(bass_plan):
        stride(b * 8, r, c)

    v = 0.85
    # A strain, phrase 1: the iconic pickup and hook
    note('D4', 0, 1); note('Eb4', 1, 1); note('E4', 2, 1); note('C5', 3, 2)
    note('E4', 5, 1); note('C5', 6, 2)
    note('E4', 8, 1); note('C5', 9, 4)  # long C
    note('C5', 13, 1); note('D5', 14, 1); note('Eb5', 15, 1)
    note('E5', 16, 1); note('C5', 17, 1); note('D5', 18, 1); note('E5', 19, 2)
    note('B4', 21, 1); note('D5', 22, 1)
    note('C5', 24, 4)
    # phrase 2: repeat with answer
    note('D4', 32, 1); note('Eb4', 33, 1); note('E4', 34, 1); note('C5', 35, 2)
    note('E4', 37, 1); note('C5', 38, 2)
    note('E4', 40, 1); note('C5', 41, 4)
    note('A4', 45, 1); note('G4', 46, 1); note('F#4', 47, 1)
    note('A4', 48, 1); note('C5', 49, 1); note('E5', 50, 2)
    note('D5', 52, 1); note('C5', 53, 1); note('A4', 54, 1)
    note('D5', 56, 4)
    # phrase 3: sequence up
    note('E5', 64, 1); note('D5', 65, 1); note('C5', 66, 1); note('A4', 67, 2)
    note('C5', 69, 1); note('D5', 70, 2)
    note('E5', 72, 1); note('C5', 73, 1); note('D5', 74, 1); note('E5', 75, 2)
    note('C5', 77, 1); note('D5', 78, 1); note('C5', 79, 1)
    note('E5', 80, 1); note('C5', 81, 1); note('D5', 82, 1); note('E5', 83, 2)
    note('B4', 85, 1); note('D5', 86, 1)
    note('C5', 88, 4)
    # final phrase: cadence
    note('C5', 96, 1); note('D5', 97, 1); note('E5', 98, 1); note('C5', 99, 1)
    note('D5', 100, 1); note('E5', 101, 2); note('C5', 103, 1)
    note('D5', 104, 1); note('C5', 105, 1); note('E5', 106, 1); note('C5', 107, 1)
    note('D5', 108, 1); note('E5', 109, 2); note('C5', 111, 1)
    note('B4', 112, 1); note('D5', 113, 1); note('C5', 114, 4)
    chord(['E4', 'G4', 'C5'], 120, 4, 0.9)
    chord(['C4', 'E4', 'G4', 'C5'], 124, 4, 1.0)

    return out

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
    os.makedirs(outdir, exist_ok=True)
    p = lambda n: os.path.join(outdir, n)

    write_wav(p('meow.wav'), meow())
    write_wav(p('meow_kitten.wav'), meow(base=680, top=1080, dur=0.45, seed=2))
    write_wav(p('yowl.wav'), meow(base=480, top=820, dur=1.3, vib=9,
                                  breathy=0.2, seed=3))
    write_wav(p('purr.wav'), purr())
    write_wav(p('munch.wav'), munch())
    write_wav(p('scratch.wav'), scratch())
    write_wav(p('crash.wav'), crash())
    write_wav(p('scoop.wav'), scoop())
    write_wav(p('jingle.wav'), jingle())
    write_wav(p('doorbell.wav'), doorbell())
    write_wav(p('chirp.wav'), chirp())
    write_wav(p('pop.wav'), pop())
    write_wav(p('success.wav'), success())
    write_wav(p('fail.wav'), fail())
    write_wav(p('thunder.wav'), thunder())
    write_wav(p('buzz.wav'), buzz())
    write_wav(p('kitten_on_the_keys.wav'), music(), gain=0.75)
    write_wav(p('the_entertainer.wav'), entertainer(), gain=0.75)

if __name__ == '__main__':
    main()
