# Arch Linux dotfiles

Back up and restore Arch Linux config files with git, and install every application those configs need on a new machine.

| File | Purpose |
| --- | --- |
| `dotfiles.sh` | Back up, restore, diff and track configs. Manages the automatic backup timer. |
| `install.sh` | Installs the packages the configs depend on (pacman + AUR), then enables services. |
| `setup.sh` | The one-command installer: installs git/rsync, clones the repo, runs `bootstrap.sh`. |
| `bootstrap.sh` | Sets up a fresh machine in one go: `install.sh`, then `restore`, then optionally the timer. |
| `dotfiles.conf` | The list of tracked paths, each followed by the packages it needs. |
| `exclude.conf` | rsync patterns that are never backed up (caches, logs, `.git/`, SSH/GPG keys). |
| `services.conf` | systemd units to enable after installing (`system` or `user` scope). |
| `packages/extra.txt` | Extra packages to always install, even if no config needs them. |
| `packages/pacman.txt`, `packages/aur.txt` | Generated on every backup: all explicitly installed packages. |
| `home/`, `root/` | The backed-up copies of files under `$HOME` and of system files such as `/etc/...`. |

Requirements: `bash`, `git`, `rsync`. `install.sh` also needs `sudo`.

## Quick start (one command)

On a fresh Arch install, log in as your normal user (one with `sudo` rights) and run:

```bash
curl -fsSL https://raw.githubusercontent.com/hereikeepmystuff-svg/claudetester/main/setup.sh | bash
```

This installs `git` and `rsync`, clones this repo to `~/dotfiles`, installs every package the configs need, restores the configs, and asks whether to turn on daily automatic backups. Running it again updates the checkout and repeats the setup.

To pass options to `install.sh`, put them after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/hereikeepmystuff-svg/claudetester/main/setup.sh | bash -s -- --snapshot --noconfirm
```

To clone somewhere else or from a fork, set `DOTFILES_DIR`, `DOTFILES_REPO` or `DOTFILES_BRANCH`, e.g. `curl -fsSL .../setup.sh | DOTFILES_DIR=~/.dotfiles bash`.

## Setup on your current machine

```bash
git clone <your-repo-url> ~/dotfiles && cd ~/dotfiles
$EDITOR dotfiles.conf            # list your configs and their packages
./dotfiles.sh backup --push      # copy configs into the repo, commit and push
./dotfiles.sh timer enable       # back up automatically every day
```

Use a **private** repository: the configs can contain personal details.

### Tracking configs

Each line in `dotfiles.conf` is a path followed by the packages that path needs:

```
.config/nvim        neovim ripgrep fd
.config/sway        sway swaybg swayidle aur:swaysome
/etc/pacman.conf    pacman-contrib
```

- Paths are relative to `$HOME`. Absolute paths are system files: they are restored with `sudo` and stored under `root/`.
- The installer works out whether a package comes from the official repos or the AUR. Prefix a name with `aur:` to force the AUR.
- Paths that don't exist on this machine are skipped with a warning. You can keep one list for several machines.

To start tracking something, use `add`. It appends the line to `dotfiles.conf` and backs the path up:

```bash
./dotfiles.sh add ~/.config/foot foot
```

## Commands

```bash
./dotfiles.sh backup [paths]          # system -> repo (also saves the package lists)
./dotfiles.sh backup --commit         # ...and git commit
./dotfiles.sh backup --push           # ...and commit and push
./dotfiles.sh status                  # which tracked paths changed (+ new, ~ changed, - deleted)
./dotfiles.sh diff [paths]            # unified diff from the repo copy to the system
./dotfiles.sh restore [paths]         # repo -> system (asks for confirmation; -y skips it)
./dotfiles.sh list                    # tracked paths and their packages
./dotfiles.sh timer enable|disable|status [--calendar weekly] [--no-push]
```

Every command takes `-n/--dry-run`.

**Backup** makes the repo copy of a directory match the system exactly, so files you deleted locally are also removed from the repo. Before committing, it refuses to continue if it finds anything that looks like a private key.

**Restore** never deletes files from your system. Before it overwrites a file, it saves the old version to `~/.local/state/dotfiles/backups/<timestamp>/`, so you can undo the restore.

### Automatic backups

`./dotfiles.sh timer enable` installs a systemd user timer: `~/.config/systemd/user/dotfiles-backup.timer`. The timer runs `dotfiles.sh backup --push` daily. If the machine was off at the scheduled time, the backup runs once it is back on.

- Change the schedule with `--calendar`. It takes any `OnCalendar=` value, e.g. `weekly` or `*-*-* 20:00`.
- Use `--no-push` to only commit locally.
- To push without a prompt, the remote needs credentials that don't ask for input: an SSH key loaded in an agent, or a credential helper.
- Logs: `journalctl --user -u dotfiles-backup.service`.

## Restoring on a new machine

The [quick start](#quick-start-one-command) command does all of this. To do it by hand instead:

```bash
sudo pacman -S --needed git rsync
git clone <your-repo-url> ~/dotfiles && cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` takes the same options as `install.sh`. You can also run the steps yourself:

```bash
./install.sh                  # packages from dotfiles.conf + packages/extra.txt
./install.sh --snapshot       # also everything that was explicitly installed on the old machine
./dotfiles.sh restore
```

`install.sh` options:

| Option | Effect |
| --- | --- |
| `-s, --snapshot` | Also install everything in `packages/pacman.txt` and `packages/aur.txt`. |
| `--no-aur` | Install repo packages only. |
| `--helper paru\|yay` | Pick the AUR helper. If none is installed, `yay-bin` is built automatically. |
| `--noconfirm` | Don't ask before installing. |
| `--no-services` | Don't enable the units in `services.conf`. |
| `-n, --dry-run` | Show what would be installed. |

The installer runs a full `pacman -Syu` (never a partial upgrade) and skips packages that are already installed.

## Notes

- Files are copied, not symlinked. Editing a config doesn't change the repo until the next backup, which the timer handles.
- Git stores only the executable bit, not full file permissions. Keep system files that need special modes (e.g. `/etc/sudoers.d/*`) out of the repo, or fix their modes after a restore.
- Secrets: `.ssh/`, `.gnupg/`, `*.pem`, `*.key` and similar are excluded by default. Add your own patterns to `exclude.conf`.
