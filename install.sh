#!/usr/bin/env bash
# Install every application the tracked configs depend on.
#
# Packages come from:
#   - dotfiles.conf      the packages listed next to each tracked path
#   - packages/extra.txt hand-maintained extras not tied to a config
#   - packages/pacman.txt + packages/aur.txt (only with --snapshot), the full
#     list of explicitly installed packages captured by 'dotfiles.sh backup'
#
# Repo packages are installed with pacman, everything else through an AUR
# helper (paru or yay; yay-bin is bootstrapped if neither is present).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

usage() {
    cat <<USAGE
Usage: ${0##*/} [options]

Options:
  -s, --snapshot      Also install the full package snapshot (packages/pacman.txt, aur.txt).
      --no-aur        Skip AUR packages (and don't bootstrap an AUR helper).
      --no-services   Don't enable the services listed in services.conf.
      --helper NAME   AUR helper to use: paru or yay (default: whichever is installed, else yay).
      --noconfirm     Pass --noconfirm to pacman and the AUR helper.
  -n, --dry-run       Show what would be installed without changing anything.
  -h, --help          Show this help.
USAGE
}

SNAPSHOT=0
NO_AUR=0
NO_SERVICES=0
HELPER=""
NOCONFIRM=()

while (( $# )); do
    case $1 in
        -s|--snapshot) SNAPSHOT=1 ;;
        --no-aur)      NO_AUR=1 ;;
        --no-services) NO_SERVICES=1 ;;
        --helper)      HELPER="${2:?--helper needs a value}"; shift ;;
        --noconfirm)   NOCONFIRM=(--noconfirm) ;;
        -n|--dry-run)  DRY_RUN=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
done

preflight() {
    [[ -f /etc/arch-release ]] || warn "/etc/arch-release not found; this script targets Arch Linux"
    (( EUID != 0 )) || die "run as your normal user, not root (sudo is used where needed; makepkg refuses root)"
    need_cmd pacman pacman
    command -v sudo >/dev/null 2>&1 || die "sudo is required (as root: pacman -S sudo, then add yourself to sudoers)"
}

# Collect the wanted package names, de-duplicated, keeping 'aur:' prefixes.
collect_packages() {
    {
        conf_packages
        list_file "$PKG_DIR/extra.txt"
        if (( SNAPSHOT )); then
            list_file "$PKG_DIR/pacman.txt"
            list_file "$PKG_DIR/aur.txt" | sed 's/^/aur:/'
        fi
    } | awk 'NF && !seen[$0]++'
}

REPO_PKGS=()
AUR_PKGS=()

# Split packages into repo and AUR. Names prefixed with 'aur:' are forced to AUR;
# anything else is installed from the repos if pacman knows it (as a package or a
# group), otherwise it is assumed to live in the AUR.
classify_packages() {
    local pkg name
    local -A repo_seen=() aur_seen=()
    while IFS= read -r pkg; do
        if [[ $pkg == aur:* ]]; then
            name="${pkg#aur:}"
            # A snapshot package may be listed as aur: but actually be in the repos
            # now (e.g. it moved); prefer the repos in that case.
            if pacman -Si -- "$name" >/dev/null 2>&1; then
                repo_seen[$name]=1
            else
                aur_seen[$name]=1
            fi
        elif pacman -Si -- "$pkg" >/dev/null 2>&1 || pacman -Sg -- "$pkg" >/dev/null 2>&1; then
            repo_seen[$pkg]=1
        else
            aur_seen[$pkg]=1
        fi
    done < <(collect_packages)
    mapfile -t REPO_PKGS < <(printf '%s\n' "${!repo_seen[@]}" | sed '/^$/d' | sort)
    mapfile -t AUR_PKGS < <(printf '%s\n' "${!aur_seen[@]}" | sed '/^$/d' | sort)
}

install_repo_packages() {
    if (( ${#REPO_PKGS[@]} == 0 )); then
        info "no repo packages to install"
        return
    fi
    info "installing ${#REPO_PKGS[@]} repo packages: ${REPO_PKGS[*]}"
    # Full -Syu rather than -Sy to avoid a partial upgrade.
    run sudo pacman -Syu --needed "${NOCONFIRM[@]}" -- "${REPO_PKGS[@]}"
}

detect_helper() {
    if [[ -n $HELPER ]]; then
        [[ $HELPER == paru || $HELPER == yay ]] || die "--helper must be paru or yay"
        command -v "$HELPER" >/dev/null 2>&1 && return 0
        bootstrap_helper "$HELPER"
        return
    fi
    local h
    for h in paru yay; do
        if command -v "$h" >/dev/null 2>&1; then HELPER="$h"; return; fi
    done
    HELPER=yay
    bootstrap_helper yay
}

# Build an AUR helper from its -bin package so no compiler toolchain is needed.
bootstrap_helper() {
    local name="$1" build
    info "bootstrapping AUR helper: $name"
    run sudo pacman -S --needed "${NOCONFIRM[@]}" -- git base-devel
    if (( DRY_RUN )); then
        run git clone "https://aur.archlinux.org/$name-bin.git" "<tmpdir>"
        run makepkg -si "${NOCONFIRM[@]}"
        return
    fi
    build="$(mktemp -d)"
    git clone --depth 1 "https://aur.archlinux.org/$name-bin.git" "$build/$name-bin"
    (cd "$build/$name-bin" && makepkg -si "${NOCONFIRM[@]}")
    rm -rf -- "${build:?}"
    command -v "$name" >/dev/null 2>&1 || die "failed to install $name"
    ok "$name installed"
}

install_aur_packages() {
    if (( ${#AUR_PKGS[@]} == 0 )); then
        info "no AUR packages to install"
        return
    fi
    if (( NO_AUR )); then
        warn "skipping ${#AUR_PKGS[@]} AUR packages (--no-aur): ${AUR_PKGS[*]}"
        return
    fi
    detect_helper
    info "installing ${#AUR_PKGS[@]} AUR packages with $HELPER: ${AUR_PKGS[*]}"
    run "$HELPER" -S --needed "${NOCONFIRM[@]}" -- "${AUR_PKGS[@]}"
}

# services.conf lines look like 'system NetworkManager.service' or 'user pipewire.socket'.
enable_services() {
    (( NO_SERVICES )) && return
    [[ -f $SERVICES_FILE ]] || return 0
    local line scope unit
    while IFS= read -r line || [[ -n $line ]]; do
        line="$(_clean_line "$line")"
        [[ -z $line ]] && continue
        read -r scope unit _ <<<"$line"
        case $scope in
            system) run sudo systemctl enable --now "$unit" || warn "could not enable $unit" ;;
            user)   run systemctl --user enable --now "$unit" || warn "could not enable user unit $unit" ;;
            *)      warn "services.conf: unknown scope '$scope' (expected system or user)"; continue ;;
        esac
        info "enabled $scope unit $unit"
    done <"$SERVICES_FILE"
}

main() {
    preflight
    info "resolving packages..."
    (( DRY_RUN )) || sudo pacman -Sy >/dev/null   # fresh sync DBs so classification is accurate
    classify_packages
    install_repo_packages
    install_aur_packages
    enable_services
    ok "all dependencies installed"
}

main
