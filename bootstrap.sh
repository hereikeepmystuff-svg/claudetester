#!/usr/bin/env bash
# Set up a fresh Arch install from this repo in one go:
#   1. install every package the configs depend on (install.sh)
#   2. restore the configs (dotfiles.sh restore)
#   3. optionally enable the automatic backup timer
#
# Any options are passed through to install.sh (e.g. --snapshot, --noconfirm).
set -euo pipefail

DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=lib/common.sh
source "$DIR/lib/common.sh"

"$DIR/install.sh" "$@"
"$DIR/dotfiles.sh" restore

if confirm "Enable the daily automatic backup timer?"; then
    "$DIR/dotfiles.sh" timer enable
fi
ok "bootstrap finished — log out and back in to pick up shell/session changes"
