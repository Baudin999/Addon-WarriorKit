#!/usr/bin/env bash
# Bakes src/Media/Round.tga, the disc the gear page draws its icons inside.
#
# One asset doing two jobs, which is why it is a disc with a soft rim rather
# than two files. Given to AddMaskTexture it clips a spell icon into a circle
# and fades the last few texels of it to nothing, which is the whole point: an
# icon that stops at a line reads as a sticker stuck on a panel, and an icon
# that goes soft at its own edge reads as part of the page. Given to
# SetVertexColor as an ordinary texture it is the quality colour behind that
# icon, drawn a little wider, so the fade lands on purple or on green rather
# than on the panel.
#
# The ramp is the only decision in here and it is two numbers. SOLID is how far
# out the disc is still fully opaque and RIM is where it reaches nothing, both
# as a fraction of the half width. Everything between them is a smoothstep,
# because a linear ramp has a visible corner at each end and this does not.
#
# 128 rather than 64. The disc draws at about 36 pixels, so 64 carries the shape
# perfectly well, but the ramp is eight texels wide at 64 and the banding in it
# shows against a dark panel. Both sides are a power of two because the client
# will not draw a texture whose sides are not, and scripts/check.sh gates that.
#
# Written straight rather than through ImageMagick. A 32 bit uncompressed TGA is
# an 18 byte header and a run of BGRA, the client reads exactly that, and a
# curve written as a curve is a curve anybody can change.
#
#   ./bake-round.sh
#
# The output is 64 KB and is committed, because it is what the addon ships.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="src/Media/Round.tga"
SIZE="${ROUND_SIZE:-128}"
SOLID="${ROUND_SOLID:-0.80}"
RIM="${ROUND_RIM:-1.00}"

python3 - "$OUT" "$SIZE" "$SOLID" "$RIM" <<'PY' || exit 1
import struct, sys

path, size, solid, rim = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])

# The middle of the texture in pixel coordinates, and the half width a radius is
# measured against. A 128 wide texture has its centre at 63.5 rather than at 64,
# and using 64 puts the disc half a pixel down and to the right of where it goes.
mid = (size - 1) / 2.0
half = size / 2.0


def alpha(x, y):
	r = ((x - mid) ** 2 + (y - mid) ** 2) ** 0.5 / half
	if r <= solid:
		return 255
	if r >= rim:
		return 0
	t = (r - solid) / (rim - solid)
	return int(round(255 * (1.0 - t * t * (3.0 - 2.0 * t))))


# Uncompressed true colour, origin at the top left, eight bits of alpha. That
# descriptor byte is what `file` reports as "top", and it is what
# src/Media/Icon.tga already carries.
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)

# White under the alpha rather than black. A mask reads the alpha alone, but the
# same file is drawn as an ordinary texture for the quality ring and
# SetVertexColor multiplies: white takes the colour it is given, black stays
# black whatever it is given.
rows = bytearray()
for y in range(size):
	for x in range(size):
		a = alpha(x, y)
		rows += bytes((255, 255, 255, a))

with open(path, "wb") as f:
	f.write(header)
	f.write(rows)
PY

printf 'wrote %s\n' "$OUT"
