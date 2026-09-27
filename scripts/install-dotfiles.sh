#!/usr/bin/env bash
# ========================
#  install-dotfiles.sh
#  Links dotfiles/ into $HOME and renders ktemplated/ into it.
#
#  Usage: ./install-dotfiles.sh [--dry-run] [--force] [--target DIR]
# ========================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DOTFILES_DIR="$ROOT_DIR/dotfiles"
KTEMPLATED_DIR="$ROOT_DIR/ktemplated"

DRY_RUN=0
FORCE=0
TARGET="$HOME"
# A while loop, not a for loop: options that take a value consume the next
# argument, and a for loop iterates over a snapshot of "$@" that shift
# cannot reorder.
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=1; shift ;;
        --force|-f)   FORCE=1; shift ;;
        --target)     shift; TARGET="${1:?--target needs a directory}"; shift ;;
        -h|--help)    grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

# Rendered templates live outside the repo so they can be regenerated
# freely and never show up as repo modifications.
RENDER_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/automatizations/rendered"

BACKUP_DIR="$TARGET/.config-backup-$(date +%Y%m%d-%H%M%S)"

# Paths (relative to TARGET) that must stay real directories because a
# templated file has to live inside them. Computed before any linking, so
# ~/.config is never turned into a symlink when ~/.config/noctalia needs to
# hold a rendered file.
declare -A REAL_DIRS=()

# ========================
#  Helpers
# ========================

# Mark every ancestor directory of $1 as needing to be a real directory.
mark_real_dir() {
    local dir="$1"
    while [ "$dir" != "." ] && [ -n "$dir" ] && [ "$dir" != "/" ]; do
        REAL_DIRS["$dir"]=1
        dir="$(dirname "$dir")"
    done
}

# Back up whatever currently occupies $2, then place the link.
#   $1 source to link to, $2 destination path relative to TARGET
link_into() {
    local src="$1" rel="$2" dest="$TARGET/$2" dest_dir

    if [ -L "$dest" ] && [ "$(readlink -f "$dest" 2>/dev/null)" = "$(readlink -f "$src")" ]; then
        return 0
    fi

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ "$FORCE" -eq 0 ]; then
            warning "$rel already exists and is not managed by this repo"
            info "Backing it up to ${BACKUP_DIR#$TARGET/}/$rel"
            if [ "$DRY_RUN" -eq 0 ]; then
                dest_dir="$(dirname "$BACKUP_DIR/$rel")"
                mkdir -p "$dest_dir"
                mv "$dest" "$dest_dir/" 2>/dev/null || rm -rf "$dest"
            fi
        else
            info "Replacing $rel (--force)"
            [ "$DRY_RUN" -eq 0 ] && rm -rf "$dest"
        fi
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would link  $rel"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "  linked      $rel"
}

# Create $1 as a real directory if it is not one yet.
ensure_real_dir() {
    local dest="$TARGET/$1"
    if [ -L "$dest" ] && [ "$FORCE" -eq 1 ]; then
        # A previous install symlinked a directory we now need to be real.
        info "Replacing symlinked directory $1 with a real one"
        if [ "$DRY_RUN" -eq 0 ]; then
            mv "$dest" "$BACKUP_DIR/$1" 2>/dev/null || rm -f "$dest"
        fi
    fi
    [ "$DRY_RUN" -eq 1 ] || mkdir -p "$dest"
}

# Walk dotfiles/ creating one link per entry. Directories listed in
# REAL_DIRS are descended into instead of being linked wholesale.
#   $1 source dir, $2 destination path relative to TARGET
link_tree() {
    local src_root="$1" rel_root="$2" child name rel
    for child in "$src_root"/* "$src_root"/.[!.]* "$src_root"/..?*; do
        [ -e "$child" ] || continue
        name="$(basename "$child")"
        rel="${rel_root:+$rel_root/}$name"

        if [ -d "$child" ] && [ -n "${REAL_DIRS[$rel]:-}" ]; then
            ensure_real_dir "$rel"
            link_tree "$child" "$rel"
        else
            link_into "$child" "$rel"
        fi
    done
}

# Substitute the template placeholders in $1 and write to $2.
render_template() {
    local src="$1" dest="$2" dest_dir
    local git_name="${GIT_NAME:-}" git_email="${GIT_EMAIL:-}"

    [ -z "$git_name" ] && git_name="$(git config --global user.name 2>/dev/null || true)"
    [ -z "$git_email" ] && git_email="$(git config --global user.email 2>/dev/null || true)"

    dest_dir="$(dirname "$dest")"
    [ "$DRY_RUN" -eq 1 ] || { mkdir -p "$dest_dir"; }

    # @HOME@ always resolves; the git identity falls back to a visible
    # placeholder so an unconfigured checkout is obvious rather than broken.
    sed -e "s|@HOME@|$HOME|g" \
        -e "s|@USER@|$(basename "$HOME")|g" \
        -e "s|@HOSTNAME@|$(hostname)|g" \
        -e "s|@GIT_NAME@|${git_name:-<set your git name>}|g" \
        -e "s|@GIT_EMAIL@|${git_email:-<set your git email>}|g" \
        "$src" > "$dest"
}

# ========================
#  Main
# ========================
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║            Dotfiles install              ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"

[ -d "$DOTFILES_DIR" ] || error "dotfiles/ not found at $DOTFILES_DIR"
[ "$DRY_RUN" -eq 1 ] && warning "Dry run: no changes will be made."

# --- 1. Work out which directories must stay real ---
if [ -d "$KTEMPLATED_DIR" ]; then
    while IFS= read -r -d '' path; do
        mark_real_dir "$(dirname "${path#$KTEMPLATED_DIR/}")"
    done < <(find "$KTEMPLATED_DIR" -type f -print0)
fi

# --- 2. Link the plain dotfiles ---
info "Linking dotfiles/ ($(find "$DOTFILES_DIR" -type f | wc -l) files)"
link_tree "$DOTFILES_DIR" ""

# --- 3. Render the templated files, then link them ---
if [ -d "$KTEMPLATED_DIR" ]; then
    info "Rendering ktemplated/ ($(find "$KTEMPLATED_DIR" -type f | wc -l) files)"
    while IFS= read -r -d '' path; do
        rel="${path#$KTEMPLATED_DIR/}"
        rendered="$RENDER_DIR/$rel"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  would render $rel"
        else
            render_template "$path" "$rendered"
            chmod 0644 "$rendered"
        fi
        # The rendered file is the symlink target, so nothing in it should
        # be executable unless it is a script.
        case "$rel" in
            *.sh) [ "$DRY_RUN" -eq 1 ] || chmod +x "$rendered" ;;
        esac
        link_into "$rendered" "$rel"
    done < <(find "$KTEMPLATED_DIR" -type f -print0 | sort -z)
fi

# --- 4. Restore the executable bit on the scripts shipped as dotfiles ---
while IFS= read -r -d '' path; do
    [ "$DRY_RUN" -eq 0 ] && chmod +x "$path"
done < <(find "$DOTFILES_DIR" -type f -name '*.sh' -print0)

# --- 5. Secrets: fish exports are per-user, never committed ---
if [ -f "$TARGET/.config/fish/conf.d/secrets.fish" ]; then
    success "Kept existing ~/.config/fish/conf.d/secrets.fish (never overwritten)"
else
    info "No secrets.fish found. Create one for private exports, e.g.:"
    echo -e "      ${CYAN}mkdir -p ~/.config/fish/conf.d${RESET}"
    echo -e "      ${CYAN}echo 'set -gx MY_TOKEN \"...\"' > ~/.config/fish/conf.d/secrets.fish${RESET}"
fi

echo ""
success "Dotfiles installed"
[ -d "$BACKUP_DIR" ] && info "Backups of pre-existing files: ${BACKUP_DIR#$TARGET/}"
echo -e "  ${YELLOW}Log out and back in for the shell changes to take effect.${RESET}"
echo -e "  Re-apply the Hyprland config with: ${CYAN}hyprctl reload${RESET}"
