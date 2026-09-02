#!/usr/bin/env bash
# Bakes src/Media/Hatch.tga, the diagonal weave the party and raid tiles draw
# their missing health through.
#
# One 32 by 32 tile, white on nothing, repeated across a tile by texture
# coordinates rather than stretched to fit it. That is the whole reason it is
# baked rather than drawn: a stripe stretched to a tile is a stripe whose width
# says how hurt somebody is, and the point of the weave is that it reads the
# same on a raid cell and on a party tile.
#
# The period divides the side, so the pattern meets itself at every edge and a
# wall of tiles has no seam. Change one of the three numbers below and check the
# other two still divide.
#
# Run from anywhere in the repository. It writes one file and prints its size.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import struct

SIDE = 32       # a power of two, which is the only size the client will draw
PERIOD = 8      # divides SIDE, or the tile does not meet itself
STRIPE = 3      # how much of the period is drawn
ALPHA = 230     # the mark's own strength; the tint on top scales it down again

pixels = bytearray()
for y in range(SIDE):
    for x in range(SIDE):
        on = ((x + y) % PERIOD) < STRIPE
        pixels += bytes((255, 255, 255, ALPHA if on else 0))

# Uncompressed 32 bit BGRA, top row first, which is the one TGA shape every
# client reads without an opinion about it.
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0,
                     SIDE, SIDE, 32, 0x28)
with open("src/Media/Hatch.tga", "wb") as out:
    out.write(header + bytes(pixels))
print("src/Media/Hatch.tga %dx%d" % (SIDE, SIDE))
PY
