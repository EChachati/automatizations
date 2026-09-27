#!/usr/bin/env bash
# Oculta/muestra apps del launcher de Noctalia (y cualquier menu XDG)
# segun la lista en ~/.config/noctalia/hidden-apps.list.
#
# Formato de la lista:
#   <id.desktop> = true    -> oculta la app (crea override con NoDisplay=true)
#   <id.desktop> = false   -> la muestra de nuevo (borra el override)
#
# Uso: hide-apps.sh
set -euo pipefail

LIST="${NOCTALIA_HIDDEN_APPS:-$HOME/.config/noctalia/hidden-apps.list}"
TARGET_DIR="$HOME/.local/share/applications"
mkdir -p "$TARGET_DIR"

# Orden de busqueda: lo mas especifico primero
SOURCE_DIRS=(
  "$HOME/.local/share/flatpak/exports/share/applications"
  "$HOME/.local/share/applications"
  "/var/lib/flatpak/exports/share/applications"
  "/usr/local/share/applications"
  "/usr/share/applications"
)
for dir in ${XDG_DATA_DIRS:-}; do
  [[ "$dir" == *applications ]] && SOURCE_DIRS+=("$dir")
done
SOURCE_DIRS=($(printf '%s\n' "${SOURCE_DIRS[@]}" | awk '!seen[$0]++'))

find_source() {
  local name=$1
  for d in "${SOURCE_DIRS[@]}"; do
    [[ -f "$d/$name" ]] && { printf '%s\n' "$d/$name"; return 0; }
  done
  return 1
}

normalize() {
  local n=$1
  [[ "$n" == *.desktop ]] || n="$n.desktop"
  printf '%s\n' "$n"
}

hide_app() {
  local name src override
  name=$(normalize "$1")
  override="$TARGET_DIR/$name"
  if [[ -f "$override" ]]; then
    grep -q '^NoDisplay=true' "$override" || printf 'NoDisplay=true\n' >> "$override"
    echo "oculta (ya estaba): $name"
    return
  fi
  if src=$(find_source "$name"); then
    cp "$src" "$override"
    printf 'NoDisplay=true\n' >> "$override"
    echo "oculta: $name"
  else
    echo "no se encontro $name en ningun directorio de aplicaciones"
  fi
}

show_app() {
  local name
  name=$(normalize "$1")
  if [[ -f "$TARGET_DIR/$name" ]]; then
    rm "$TARGET_DIR/$name"
    echo "visible: $name"
  else
    echo "visible (no habia override): $name"
  fi
}

[[ -f "$LIST" ]] || { echo "no existe la lista: $LIST"; exit 1; }

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"                 # quitar comentarios
  [[ "$line" != *"="* ]] && continue # lineas sin valor se ignoran
  id="${line%%=*}"
  val="${line#*=}"
  id="${id//[[:space:]]/}"
  val="${val//[[:space:]]/}"
  val="${val,,}"                     # a minusculas
  [[ -z "$id" ]] && continue
  case "$val" in
    true|1|yes|si|s) hide_app "$id" ;;
    false|0|no|n)    show_app "$id" ;;
    *) echo "valor invalido para $id: '$val' (usa true/false)";;
  esac
done < "$LIST"

echo
echo "Recarga Noctalia o relogueate para aplicar los cambios."