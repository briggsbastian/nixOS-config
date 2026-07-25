#!/usr/bin/env bash
# Procedurally generates the Hyprland rice's default wallpaper: a dark
# Shibuya-punk/synthwave night skyline -- gradient sky, two corner glows
# (magenta/cyan), a glowing horizon band, and a perspective neon grid floor.
# Built at nix-build time (see ../wallpaper.nix) so the rice needs no binary
# image asset checked into the repo.
set -euo pipefail

W="${1:-5120}"
H="${2:-1440}"
OUT="${3:-out.png}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BG1="#060008"
BG2="#0e0518"
MAGENTA="#ff2bd6"
CYAN="#22e5ff"

# 1. base vertical gradient sky (opaque)
magick -size "${W}x${H}" gradient:"${BG1}-${BG2}" "$TMP/sky.png"

# 2. corner glows: opaque radial gradients fading to BLACK (no alpha
#    involved at all), screen-composited once each onto the sky. Screening
#    against black is a no-op, so this only lightens near each glow's peak.
#    The 2Wx2H canvas's center (W,H) is the glow's peak; cropping a WxH box
#    whose corner lands exactly on (W,H) puts the peak at that box's
#    matching local corner: +0+H -> top-right; +W+0 -> bottom-left. A pow
#    curve steepens the falloff so the glow stays a contained pool of color
#    instead of washing the whole frame.
magick -size "$((W * 2))x$((H * 2))" radial-gradient:"${CYAN}-black" \
  -crop "${W}x${H}+0+${H}" +repage -evaluate pow 7 "$TMP/glow_cyan.png"
magick -size "$((W * 2))x$((H * 2))" radial-gradient:"${MAGENTA}-black" \
  -crop "${W}x${H}+${W}+0" +repage -evaluate pow 7 "$TMP/glow_magenta.png"

magick "$TMP/sky.png" "$TMP/glow_cyan.png" -compose screen -composite "$TMP/step1.png"
magick "$TMP/step1.png" "$TMP/glow_magenta.png" -compose screen -composite "$TMP/step2.png"

# From here on, every layer is a TRUE RGBA image (transparent, not black,
# where it has no content) composited with the default alpha-aware 'over' --
# this is what keeps colors saturated instead of washing toward white the
# way chained 'screen' composites do.

HORIZON=$((H * 62 / 100))
FLOOR_H=$((H - HORIZON))

# 3. horizon glow band: transparent -> magenta -> transparent, real alpha.
magick -size "${W}x60" gradient:"none-${MAGENTA}" "$TMP/hbar_top.png"
magick -size "${W}x60" gradient:"${MAGENTA}-none" "$TMP/hbar_bot.png"
magick "$TMP/hbar_top.png" "$TMP/hbar_bot.png" -append "$TMP/hbar.png"
magick "$TMP/step2.png" "$TMP/hbar.png" -gravity NorthWest -geometry "+0+$((HORIZON - 60))" -compose over -composite "$TMP/step3.png"

# 4. perspective grid floor: drawn with semi-transparent strokes on a real
#    transparent canvas, so the perspective distort's antialiased edges keep
#    real alpha and composite cleanly with 'over'.
CX=$((W / 2))
magick -size "${W}x${FLOOR_H}" xc:none "$TMP/grid.png"

N_V=40
SPACING=$((W / N_V))
DRAW_ARGS=()
x=0
while [ "$x" -le "$W" ]; do
  DRAW_ARGS+=(-draw "stroke ${CYAN}e8 stroke-width 2 line $x,0 $x,$FLOOR_H")
  x=$((x + SPACING))
done
magick "$TMP/grid.png" "${DRAW_ARGS[@]}" "$TMP/grid.png"

DRAW_ARGS=()
y=6
gap=6
while [ "$y" -lt "$FLOOR_H" ]; do
  DRAW_ARGS+=(-draw "stroke ${MAGENTA}e8 stroke-width 2 line 0,$y $W,$y")
  y=$((y + gap))
  gap=$((gap * 118 / 100 + 1))
done
magick "$TMP/grid.png" "${DRAW_ARGS[@]}" "$TMP/grid.png"

# perspective-distort the grid so verticals converge toward a vanishing
# point at the horizon center; the bottom edge (nearest the viewer) stays
# full width.
magick "$TMP/grid.png" -virtual-pixel transparent \
  -distort Perspective \
  "0,0 $((CX - 40)),0  ${W},0 $((CX + 40)),0  0,${FLOOR_H} 0,${FLOOR_H}  ${W},${FLOOR_H} ${W},${FLOOR_H}" \
  "$TMP/grid_persp.png"

# neon bloom: a blurred copy screened under the crisp lines, so the grid
# glows instead of reading as flat vector strokes.
magick "$TMP/grid_persp.png" -blur 0x6 "$TMP/grid_glow.png"
magick "$TMP/grid_glow.png" "$TMP/grid_persp.png" -compose over -composite "$TMP/grid_final.png"

magick "$TMP/step3.png" "$TMP/grid_final.png" -gravity NorthWest -geometry "+0+${HORIZON}" -compose over -composite "$TMP/step4.png"

# 5. scanlines across whole image (real alpha, subtle).
magick -size "${W}x2" xc:none -draw "stroke #00000060 stroke-width 1 line 0,0 ${W},0" "$TMP/scanline.png"
magick -size "${W}x${H}" tile:"$TMP/scanline.png" "$TMP/scanlines_full.png"
magick "$TMP/step4.png" "$TMP/scanlines_full.png" -compose over -composite "$TMP/step5.png"

# 6. grain
magick -size "${W}x${H}" xc:gray50 +noise Gaussian -colorspace Gray -attenuate 0.25 "$TMP/grain.png"
magick "$TMP/step5.png" "$TMP/grain.png" -compose overlay -composite "$TMP/step6.png"

# 7. vignette
magick "$TMP/step6.png" -background black -vignette "0x$((H / 3))" "$OUT"
