#!/usr/bin/env bash
# Regenera la lista de apps de hidden-apps.list (añade nuevas, quita
# desinstaladas) conservando los valores true/false que ya tengas puestos.
#
# Uso: sync-hidden-apps.sh
set -euo pipefail

LIST="${NOCTALIA_HIDDEN_APPS:-$HOME/.config/noctalia/hidden-apps.list}"
OVERRIDE_DIR="$HOME/.local/share/applications"

SOURCE_DIRS=(
  "$HOME/.local/share/flatpak/exports/share/applications"
  "$OVERRIDE_DIR"
  "/var/lib/flatpak/exports/share/applications"
  "/usr/local/share/applications"
  "/usr/share/applications"
)
for dir in ${XDG_DATA_DIRS:-}; do
  [[ "$dir" == *applications ]] && SOURCE_DIRS+=("$dir")
done
SOURCE_DIRS=($(printf '%s\n' "${SOURCE_DIRS[@]}" | awk '!seen[$0]++'))

# Leer estado actual de la lista: id -> true/false
declare -A state
if [[ -f "$LIST" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ "$line" == *"="* ]] || continue
    id="${line%%=*}"; val="${line#*=}"
    id="${id//[[:space:]]/}"; val="${val,,}"; val="${val//[[:space:]]/}"
    [[ -z "$id" ]] && continue
    case "$val" in
      true|1|yes|si|s)      state[$id]=true ;;
      false|0|no|n|"")      state[$id]=false ;;
    esac
  done < "$LIST"
fi

# Recolectar apps instaladas (nombre de archivo unico, prioridad de director)
declare -A best
order=()
for d in "${SOURCE_DIRS[@]}"; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*.desktop; do
    [[ -f "$f" ]] || continue
    b=$(basename "$f")
    [[ -n "${best[$b]:-}" ]] && continue
    best[$b]="$f"; order+=("$b")
  done
done

tmp=$(mktemp)
{
  printf '# Lista de apps del menu. Pon true para OCULTAR, false para MOSTRAR.\n'
  printf '# Tras editar, ejecuta: ~/.config/noctalia/hide-apps.sh\n'
  printf '# Para refrescar esta lista: ~/.config/noctalia/sync-hidden-apps.sh\n'
  printf '#\n'
  printf '# Formato:  <id.desktop> = true|false     # Nombre\n'
  printf '#\n'
} > "$tmp"

added=0; kept=0
for b in $(printf '%s\n' "${order[@]}" | sort); do
  f="${best[$b]}"

  # Ya ocultada por override del usuario -> siempre true
  if [[ -f "$OVERRIDE_DIR/$b" ]]; then
    val=true
  # No aparece en menus -> no la listamos
  elif grep -qE '^(NoDisplay|Hidden)=true' "$f"; then
    continue
  # Respetar la eleccion previa del usuario
  elif [[ -n "${state[$b]:-}" ]]; then
    val="${state[$b]}"
  else
    val=false
    added=$((added+1))
  fi
  [[ -n "${state[$b]:-}" ]] && kept=$((kept+1))

  name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
  printf '%-45s = %-5s # %s\n' "$b" "$val" "${name:-$b}" >> "$tmp"
done

cp "$tmp" "$LIST"
rm -f "$tmp"
echo "Lista actualizada: $LIST"
echo "  $added nueva(s) en false, $kept conservadas."
echo "Ahora ejecuta: ~/.config/noctalia/hide-apps.sh"