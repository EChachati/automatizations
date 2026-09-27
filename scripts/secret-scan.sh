#!/usr/bin/env bash
# ========================
#  secret-scan.sh
#  Fails when a file looks like it holds a credential.
#
#  This is a backstop, not a guarantee. It is a blocklist by nature, and
#  blocklists fail open: it catches the common shapes and misses whatever
#  nobody thought of. The real boundary is config/managed-paths.list.
#  Think of this as the thing that turns a plausible accident into a
#  no-op, not as the thing that makes committing safe.
#
#  Usage: ./secret-scan.sh [--staged] [FILE_OR_DIR...]
# ========================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# label|extended-regex
# Labels and expressions live in two parallel arrays rather than in one
# "label|regex" string. The single-string form looked tidier but split on the
# first "|", which any alternation inside a regex destroys: the shell export
# pattern below collapsed to "^[[:space:]]*(export", grep rejected it, and
# because the loop treats a grep error the same as no match, a broken
# expression became an invisible hole rather than a visible failure.
PATTERN_LABELS=(
    'private key'
    'aws access key'
    'github token'
    'github pat'
    'slack token'
    'discord bot token'
    'stripe key'
    'google api key'
    'jwt'
    'openai key'
    'anthropic key'
    'protonvpn'
    'generic assignment'
    'shell export'
)
PATTERN_RES=(
    'BEGIN (RSA |OPENSSH |EC |PGP |DSA )?PRIVATE KEY'
    'AKIA[0-9A-Z]{16}'
    'gh[pousr]_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'xox[abprs]-[A-Za-z0-9-]{10,}'
    '[MN][A-Za-z0-9_-]{23}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27}'
    '(sk|rk)_(live|test)_[A-Za-z0-9]{20,}'
    'AIza[0-9A-Za-z_-]{35}'
    '(eyJ[A-Za-z0-9_-]{8,}\.){2}[A-Za-z0-9_-]{8,}'
    'sk-[A-Za-z0-9]{20,}'
    'sk-ant-[A-Za-z0-9_-]{20,}'
    '(pmt|psk)-[A-Za-z0-9]{20,}'
    '(password|passwd|secret|token|api[_-]?key|client[_-]?secret|private[_-]?key)[[:space:]]*[:=][[:space:]]*.?[A-Za-z0-9/+_-]{12,}'
    # The fish form of an export has no "=" at all, and the variable name is
    # the only hint there is. "set -gx MYX_CLIENT_ID \"...\"" has no
    # separator and matches no word in the pattern above, so a real
    # credential in a real per-user secrets file reported clean.
    '^[[:space:]]*(export|set[[:space:]]+(-[[:alpha:]]+[[:space:]]+)*)[[:space:]]*[A-Za-z_]*(SECRET|TOKEN|PASSWORD|PASSWD|APIKEY|API_KEY|ACCESS_KEY|CLIENT_ID|CLIENT_SECRET|PRIVATE_KEY|CREDENTIALS?)[A-Za-z_]*[[:space:]]*'
)

# Files that legitimately match and must not trip the scan.
skip_file() {
    case "$1" in
        */.git/*|*/node_modules/*) return 0 ;;
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.ico) return 0 ;;
        *.woff|*.woff2|*.ttf|*.otf) return 0 ;;
        *.mp3|*.mp4|*.mkv|*.webm|*.iso|*.zip) return 0 ;;
        packages/versions.lock) return 0 ;;
        */.gitignore|*/.gitattributes) return 0 ;;
        *) return 1 ;;
    esac
}

# True when the assigned value is itself a placeholder.
#
# The test is on the whole value, never on the line. Matching a word
# anywhere is a false negative waiting to happen: "AKIAIOSFODNN7EXAMPLE",
# the canonical fake AWS key, contains "example", so a substring test
# whitelists it. The same applies to any real secret that happens to
# contain "example", "changeme" or "placeholder" inside it.
is_placeholder() {
    local line="$1" value

    # Take whatever follows the first "=", or the first ":" if there is no "=".
    value="${line#*=}"
    [ "$value" = "$line" ] && value="${line#*:}"
    [ "$value" = "$line" ] && return 1

    # Trim, drop any trailing inline comment, then unwrap quotes.
    value="${value%%#*}"
    value="${value%%;*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    value="${value//[[:space:]]/}"

    [ -z "$value" ] && return 0
    # <angled>, {{mustache}}, ${var}, $VAR
    [[ "$value" =~ ^\<.*\>$ ]] && return 0
    [[ "$value" =~ ^\{\{.*\}\}$ ]] && return 0
    [[ "$value" =~ ^\$[A-Za-z_{] ]] && return 0
    case "$(tr '[:upper:]' '[:lower:]' <<< "$value")" in
        changeme|change_me|placeholder|example|example.com|none|null|nil|"true"|"false"|todo|"") return 0 ;;
        # "your-key-here" is a placeholder as a whole value. The old
        # substring test for "your[_-]" was what whitelisted real secrets
        # containing the letters, so this is a whole-value match only.
        your|your-*|your_*|my-*-here|replace-*) return 0 ;;
        xxx*) return 0 ;;
    esac
    return 1
}

# Scan one text file. Returns 0 when clean, 1 when something matched.
#   $1 file to read, $2 name to show in the report
scan_file() {
    local file="$1" display="${2:-$1}" label pattern line lineno rc=0 i
    if [ "${#PATTERN_LABELS[@]}" -ne "${#PATTERN_RES[@]}" ]; then
        error "PATTERN_LABELS and PATTERN_RES differ in length: ${#PATTERN_LABELS[@]} vs ${#PATTERN_RES[@]}"
    fi
    for i in "${!PATTERN_RES[@]}"; do
        label="${PATTERN_LABELS[$i]}"
        pattern="${PATTERN_RES[$i]}"
        # Fail loudly on a malformed expression. Treating "grep errored" the
        # same as "no match" is how a broken pattern becomes a blind spot.
        if ! printf '' | grep -qE "$pattern" 2>/dev/null; then
            local err
            err="$(printf '' | grep -E "$pattern" 2>&1 >/dev/null)"
            [ -n "$err" ] && error "invalid pattern [$label]: $err"
        fi
        lineno=0
        # The "|| [ -n "$line" ]" is not optional: read returns false on a
        # final line with no trailing newline, so a plain loop silently drops
        # it. For a secret scanner that means a credential on the last line
        # of a file the editor did not terminate, reported as clean.
        while IFS= read -r line || [ -n "$line" ]; do
            lineno=$((lineno + 1))
            grep -qEi "$pattern" <<< "$line" || continue
            is_placeholder "$line" && continue
            # A comment naming a setting is documentation, not the value.
            # "--" only counts as a comment when followed by a space, so a
            # PEM header like -----BEGIN is not mistaken for one.
            grep -qE '^[[:space:]]*(#|\*|//|;|--[[:space:]]|$)' <<< "$line" && continue
            echo -e "  ${RED}possible secret${RESET}  ${display}:${lineno}  ${CYAN}[${label}]${RESET}"
            echo -e "      ${YELLOW}${line:0:120}${RESET}"
            rc=1
        done < "$file"
    done
    return $rc
}

# Expand directories into the text files worth scanning.
collect_files() {
    local p
    for p in "$@"; do
        if [ -d "$p" ]; then
            find "$p" \
                -type d \( -name .git -o -name node_modules -o -name buffers \) -prune -o \
                -type f -print
        elif [ -f "$p" ]; then
            printf '%s\n' "$p"
        fi
    done
}

# ========================
#  Main
# ========================
if [ $# -eq 0 ]; then
    grep '^#' "$0" | sed 's/^# \?//'
    exit 0
fi

STAGED=0
if [ "${1:-}" = "--staged" ]; then
    STAGED=1
    shift
fi

found=0
scanned=0
tmpdir=""
cleanup() { [ -n "$tmpdir" ] && rm -rf "$tmpdir"; }
trap cleanup EXIT

if [ "$STAGED" -eq 1 ]; then
    info "Scanning staged content..."
    mapfile -d '' -t staged < <(git diff --cached --name-only -z --diff-filter=ACMR)
    [ "${#staged[@]}" -eq 0 ] && { success "Nothing staged"; exit 0; }

    # Read the blob out of the index rather than the worktree: a
    # half-staged file can pass a worktree scan and still commit the
    # secret half.
    tmpdir="$(mktemp -d)"
    for f in "${staged[@]}"; do
        skip_file "$f" && continue
        blob="$(git show ":$f" 2>/dev/null)" || continue
        [ -z "$blob" ] && continue
        # Binary blobs have no text credential to leak.
        printf '%s' "$blob" | grep -qI . 2>/dev/null || continue
        scanned=$((scanned + 1))
        tmpfile="$tmpdir/$(printf '%s' "$f" | tr '/' '_')"
        printf '%s\n' "$blob" > "$tmpfile"
        scan_file "$tmpfile" "$f" || found=1
    done
else
    while IFS= read -r f || [ -n "$f" ]; do
        skip_file "$f" && continue
        # A null byte means binary, so there is no text credential to leak.
        grep -qI . "$f" 2>/dev/null || continue
        scanned=$((scanned + 1))
        scan_file "$f" || found=1
    done < <(collect_files "$@")
fi

echo ""
if [ "$found" -ne 0 ]; then
    error "Secret scan failed. Nothing was committed."
fi
[ "$scanned" -gt 0 ] && success "Secret scan clean ($scanned file(s) checked)"
exit 0
