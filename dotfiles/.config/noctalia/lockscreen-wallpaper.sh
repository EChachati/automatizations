#!/usr/bin/env bash
# Rota SOLO el wallpaper del lock screen.
#
# El wallpaper del escritorio no se toca: escribe [lockscreen].wallpaper en
# settings.toml (la capa que carga al final y pisa a config.toml) y recarga.
# NOCTALIA_SKIP_IF_SAME=1 evita recargar si el path no cambió.
set -euo pipefail

dir="${NOCTALIA_LOCK_WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"
settings="$state/settings.toml"
current="$state/lockscreen-wallpaper"

mkdir -p "$state"

[ -d "$dir" ] || exit 0

mapfile -t images < <(
  find "$dir" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.jxl' -o -iname '*.avif' \) \
    -printf '%f\n' | sort -R
)
[ "${#images[@]}" -gt 0 ] || exit 0

# Evita repetir la imagen anterior cuando hay alternativas.
if [ "${#images[@]}" -gt 1 ]; then
  for _ in 1 2 3 4 5; do
    pick="${images[0]}"
    [ "$pick" != "$(cat "$current" 2>/dev/null || true)" ] && break
    images=("${images[@]:1}")
  done
fi
pick="${images[0]}"
path="$dir/$pick"

[ "$path" != "$(cat "$current" 2>/dev/null || true)" ] || exit 0
printf '%s\n' "$path" > "$current"

python3 - "$settings" "$path" <<'PY'
import pathlib
import re
import sys

settings = pathlib.Path(sys.argv[1])
path = sys.argv[2].replace("\\", "\\\\").replace('"', '\\"')
line = f'wallpaper = "{path}"'

text = settings.read_text() if settings.exists() else ""
start = re.search(r"^\[lockscreen\][ \t]*$", text, re.M)

if start:
    end = len(text)
    nxt = re.search(r"^\[", text[start.end():], re.M)
    if nxt:
        end = start.end() + nxt.start()
    body = text[start.end():end]
    if re.search(r"^wallpaper[ \t]*=", body, re.M):
        body = re.sub(r"^wallpaper[ \t]*=.*$", line, body, count=1, flags=re.M)
    else:
        body = line + "\n" + body
    body = body.strip("\n")
    text = text[:start.end()] + "\n" + body + "\n\n" + text[end:].lstrip("\n")
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"\n[lockscreen]\n{line}\n"

settings.parent.mkdir(parents=True, exist_ok=True)
settings.write_text(text)
PY

noctalia msg config-reload >/dev/null
