#!/usr/bin/env bash
# Shared helpers for dotfiles.sh, install.sh and bootstrap.sh.
# shellcheck disable=SC2034  # variables are used by the sourcing scripts

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_FILE="${DOTFILES_CONF:-$REPO_DIR/dotfiles.conf}"
EXCLUDE_FILE="$REPO_DIR/exclude.conf"
SERVICES_FILE="$REPO_DIR/services.conf"
PKG_DIR="$REPO_DIR/packages"
HOME_STORE="$REPO_DIR/home"   # copies of files under $HOME
ROOT_STORE="$REPO_DIR/root"   # copies of system files (absolute paths, e.g. /etc/...)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"

QUIET=0
DRY_RUN=0

if [[ -t 1 ]]; then
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

info()  { (( QUIET )) || printf '%s::%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { (( QUIET )) || printf '%s==>%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { error "$*"; exit 1; }

# Run a command, or just print it when --dry-run is active.
run() {
    if (( DRY_RUN )); then
        printf '%s[dry-run]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
    else
        "$@"
    fi
}

confirm() {
    local reply
    read -r -p "$1 [y/N] " reply
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed (try: sudo pacman -S $2)"
}

# Strip comments and surrounding whitespace from a config line.
_clean_line() {
    local line="${1%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    printf '%s' "$line"
}

# Print every tracked path from dotfiles.conf, one per line.
# Paths are relative to $HOME, or absolute for system files.
conf_paths() {
    [[ -f $CONF_FILE ]] || die "config file not found: $CONF_FILE"
    local line path
    while IFS= read -r line || [[ -n $line ]]; do
        line="$(_clean_line "$line")"
        [[ -z $line ]] && continue
        read -r path _ <<<"$line"
        path="${path#\~/}"
        path="${path%/}"
        printf '%s\n' "$path"
    done <"$CONF_FILE"
}

# Print every package named in dotfiles.conf (fields after the path), one per line.
conf_packages() {
    [[ -f $CONF_FILE ]] || die "config file not found: $CONF_FILE"
    local line pkgs pkg
    while IFS= read -r line || [[ -n $line ]]; do
        line="$(_clean_line "$line")"
        [[ -z $line ]] && continue
        read -r _ pkgs <<<"$line"
        for pkg in $pkgs; do printf '%s\n' "$pkg"; done
    done <"$CONF_FILE"
}

# Print the non-comment words of a simple list file, one per line.
list_file() {
    [[ -f $1 ]] || return 0
    local line word
    while IFS= read -r line || [[ -n $line ]]; do
        line="$(_clean_line "$line")"
        for word in $line; do printf '%s\n' "$word"; done
    done <"$1"
}

is_system_path() { [[ $1 == /* ]]; }

# Live location of a tracked path.
live_path() {
    if is_system_path "$1"; then printf '%s' "$1"; else printf '%s/%s' "$HOME" "$1"; fi
}

# Location of a tracked path inside the repository.
store_path() {
    if is_system_path "$1"; then printf '%s%s' "$ROOT_STORE" "$1"; else printf '%s/%s' "$HOME_STORE" "$1"; fi
}
