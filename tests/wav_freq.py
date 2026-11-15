# Frequency of the strongest tone in the last 2 seconds of a WAV, by counting
# upward zero crossings:  python3 wav_freq.py file.wav
import struct, sys, wave
w = wave.open(sys.argv[1])
r, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
d = struct.unpack('<%dh' % (n * ch), w.readframes(n))[::ch]
seg = d[-2 * r:]
mean = sum(seg) / len(seg)
ups = sum(1 for a, b in zip(seg, seg[1:]) if a < mean <= b)
print(round(ups / 2.0))
