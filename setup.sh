#!/usr/bin/env bash
# One-command setup for a fresh Arch Linux machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hereikeepmystuff-svg/claudetester/main/setup.sh | bash
#
# Installs git and rsync, clones (or updates) this repo, then runs bootstrap.sh,
# which installs all packages, restores the configs and offers to enable the
# backup timer. Arguments are passed to install.sh, e.g.:
#
#   curl -fsSL .../setup.sh | bash -s -- --snapshot --noconfirm
#
# Environment overrides:
#   DOTFILES_REPO    git URL to clone   (default: this repo on GitHub)
#   DOTFILES_DIR     where to clone it  (default: ~/dotfiles)
#   DOTFILES_BRANCH  branch to check out (default: main)
set -euo pipefail

# Everything lives in main() so a partially downloaded script never runs.
main() {
    local repo="${DOTFILES_REPO:-https://github.com/hereikeepmystuff-svg/claudetester.git}"
    local dir="${DOTFILES_DIR:-$HOME/dotfiles}"
    local branch="${DOTFILES_BRANCH:-main}"

    say() { printf '\e[34m::\e[0m %s\n' "$*"; }
    die() { printf '\e[31merror:\e[0m %s\n' "$*" >&2; exit 1; }

    [[ -f /etc/arch-release ]] || die "this setup only supports Arch Linux"
    (( EUID != 0 )) || die "run as your normal user (with sudo rights), not as root"
    command -v sudo >/dev/null 2>&1 || die "sudo is required: as root run 'pacman -S sudo' and add yourself to sudoers"

    say "installing git and rsync"
    sudo pacman -S --needed --noconfirm git rsync

    if [[ -d $dir/.git ]]; then
        say "updating existing checkout in $dir"
        git -C "$dir" fetch origin "$branch"
        git -C "$dir" checkout "$branch"
        git -C "$dir" pull --ff-only origin "$branch"
    elif [[ -e $dir ]]; then
        die "$dir already exists and is not a git checkout; set DOTFILES_DIR to another path"
    else
        say "cloning $repo into $dir"
        git clone --branch "$branch" "$repo" "$dir"
    fi

    say "running bootstrap"
    # When piped through 'curl | bash', stdin is the script itself; read prompts from the terminal.
    if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then
        "$dir/bootstrap.sh" "$@" </dev/tty
    else
        "$dir/bootstrap.sh" "$@"
    fi
}

main "$@"
