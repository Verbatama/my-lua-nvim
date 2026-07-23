#!/usr/bin/env bash
# Safely update Verbatama's Neovim configuration and restore locked plugins.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/Verbatama/my-nvim-verbatama.git}"
readonly REPO_BRANCH="${NVIM_CONFIG_BRANCH:-main}"
readonly CONFIG_SUBDIR="${NVIM_CONFIG_SUBDIR:-nvim}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly BIN_DIR="${NVIM_BIN_DIR:-$HOME/.local/bin}"
readonly CONFIG_DIR="${NVIM_CONFIG_DIR:-$XDG_CONFIG_HOME/nvim}"
readonly REPO_DIR="${NVIM_CONFIG_REPO_DIR:-$XDG_DATA_HOME/my-nvim-verbatama/repo}"
readonly BACKUP_ROOT="${NVIM_BACKUP_DIR:-$XDG_DATA_HOME/my-nvim-verbatama/backups}"
readonly LAZY_DIR="$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
readonly LAZY_REPO="https://github.com/folke/lazy.nvim.git"
readonly LOCK_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/my-nvim-verbatama-update.lock"

LATEST_PLUGINS=0
SKIP_PLUGINS=0
KEEP_BACKUP=0
TMP_DIR=""
BACKUP_DIR=""
ROLLED_BACK=0
UPDATE_ACTIVE=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --latest-plugins  Update plugins to newest revisions and rewrite lazy-lock.json.
                    Default behavior restores versions committed in lazy-lock.json.
  --skip-plugins    Only update the Git repository; do not touch plugins.
  --keep-backup     Keep the pre-update repository backup even after success.
  -h, --help        Show this help.
USAGE
}

while (($#)); do
  case "$1" in
    --latest-plugins) LATEST_PLUGINS=1 ;;
    --skip-plugins) SKIP_PLUGINS=1 ;;
    --keep-backup) KEEP_BACKUP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s 2>/dev/null || true)" != Linux ]]; then
  printf 'ERROR: this updater is for Linux only.\n' >&2
  exit 1
fi

if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_RESET=''
fi

info() { printf '%s==>%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

on_error() {
  local status=$?
  trap - ERR
  if [[ "$UPDATE_ACTIVE" -eq 1 ]]; then
    restore_backup || true
  fi
  exit "$status"
}

cleanup() {
  local status=$?
  rmdir "$LOCK_DIR" 2>/dev/null || true
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap on_error ERR
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "Another update appears to be running: $LOCK_DIR"
  fi
}

normalize_git_url() {
  local url=${1%.git}
  url=${url#git@github.com:}
  url=${url#https://github.com/}
  url=${url#http://github.com/}
  printf '%s\n' "${url,,}"
}

atomic_link() {
  local target=$1 link=$2
  local temp_link="${link}.tmp.$$"
  mkdir -p "$(dirname "$link")"
  rm -f -- "$temp_link"
  ln -s -- "$target" "$temp_link"
  mv -Tf -- "$temp_link" "$link" 2>/dev/null || {
    rm -f -- "$link"
    mv -f -- "$temp_link" "$link"
  }
}

bootstrap_lazy() {
  if [[ -d "$LAZY_DIR/.git" ]]; then return 0; fi
  if [[ -e "$LAZY_DIR" || -L "$LAZY_DIR" ]]; then
    mv -- "$LAZY_DIR" "$BACKUP_DIR/lazy.nvim"
  fi
  mkdir -p "$(dirname "$LAZY_DIR")"
  info "Bootstrapping lazy.nvim"
  git clone --filter=blob:none --branch stable "$LAZY_REPO" "$LAZY_DIR"
}

run_nvim_headless() {
  local command=$1
  local nvim
  if [[ -x "$BIN_DIR/nvim" ]]; then nvim="$BIN_DIR/nvim";
  else nvim="$(command -v nvim || true)"; fi
  [[ -n "$nvim" && -x "$nvim" ]] || die "Neovim was not found. Run install.sh first."
  local config_home
  config_home="$(dirname "$CONFIG_DIR")"
  if have timeout; then
    XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
      timeout 20m "$nvim" --headless "$command" +qa
  else
    XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
      "$nvim" --headless "$command" +qa
  fi
}

restore_backup() {
  [[ "$ROLLED_BACK" -eq 0 ]] || return 0
  ROLLED_BACK=1
  UPDATE_ACTIVE=0
  warn "Update failed; restoring the previous repository."
  rm -rf -- "$REPO_DIR"
  mv -- "$BACKUP_DIR/repository" "$REPO_DIR"
  atomic_link "$REPO_DIR/$CONFIG_SUBDIR" "$CONFIG_DIR"
  if [[ "$SKIP_PLUGINS" -eq 0 && -f "$REPO_DIR/$CONFIG_SUBDIR/lazy-lock.json" ]]; then
    run_nvim_headless '+Lazy! restore' || warn "Repository rollback succeeded, but plugin rollback needs manual attention."
  fi
}

update_repository() {
  local remote current_remote stash_created=0
  current_remote="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  [[ -n "$current_remote" ]] || die "The repository has no origin remote: $REPO_DIR"
  [[ "$(normalize_git_url "$current_remote")" == "$(normalize_git_url "$REPO_URL")" ]] || \
    die "Unexpected origin remote: $current_remote"

  cp -a -- "$REPO_DIR" "$BACKUP_DIR/repository"
  UPDATE_ACTIVE=1

  if [[ -n "$(git -C "$REPO_DIR" status --porcelain=v1 --untracked-files=all)" ]]; then
    info "Temporarily stashing local changes, including untracked files"
    git -C "$REPO_DIR" stash push --include-untracked -m "automatic-update-$(date -u +%Y%m%dT%H%M%SZ)" >/dev/null
    stash_created=1
  fi

  info "Fetching origin/$REPO_BRANCH"
  git -C "$REPO_DIR" fetch --prune origin "$REPO_BRANCH"

  if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
    git -C "$REPO_DIR" checkout "$REPO_BRANCH" >/dev/null
  else
    git -C "$REPO_DIR" checkout -b "$REPO_BRANCH" --track "origin/$REPO_BRANCH" >/dev/null
  fi

  info "Rebasing local commits onto origin/$REPO_BRANCH"
  if ! git -C "$REPO_DIR" rebase "origin/$REPO_BRANCH"; then
    git -C "$REPO_DIR" rebase --abort >/dev/null 2>&1 || true
    restore_backup
    die "Git rebase failed; previous state restored."
  fi

  if [[ "$stash_created" -eq 1 ]]; then
    info "Reapplying local working-tree changes"
    if ! git -C "$REPO_DIR" stash pop --index; then
      restore_backup
      die "Local changes conflict with the update; previous state restored."
    fi
  fi

  [[ -f "$REPO_DIR/$CONFIG_SUBDIR/init.lua" ]] || {
    restore_backup
    die "Updated repository does not contain $CONFIG_SUBDIR/init.lua."
  }
}

main() {
  have git || die "git is required."
  [[ -d "$REPO_DIR/.git" ]] || die "Managed config repository not found: $REPO_DIR. Run install.sh first."
  [[ "$(basename "$CONFIG_DIR")" == nvim ]] || die "NVIM_CONFIG_DIR must end with /nvim so Neovim can discover it through XDG_CONFIG_HOME."

  acquire_lock
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nvim-update.XXXXXXXX")"
  BACKUP_DIR="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-update"
  mkdir -p "$BACKUP_DIR"

  local old_head new_head
  old_head="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
  update_repository
  new_head="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
  atomic_link "$REPO_DIR/$CONFIG_SUBDIR" "$CONFIG_DIR"

  if [[ "$SKIP_PLUGINS" -eq 0 ]]; then
    bootstrap_lazy
    if [[ "$LATEST_PLUGINS" -eq 1 ]]; then
      info "Updating plugins to latest revisions"
      run_nvim_headless '+Lazy! sync'
      if [[ -n "$(git -C "$REPO_DIR" status --porcelain -- "$CONFIG_SUBDIR/lazy-lock.json")" ]]; then
        warn "lazy-lock.json changed locally. Review and commit it to keep other machines reproducible."
      fi
    elif [[ -f "$REPO_DIR/$CONFIG_SUBDIR/lazy-lock.json" ]]; then
      info "Restoring plugin revisions from lazy-lock.json"
      run_nvim_headless '+Lazy! restore'
    else
      warn "No lazy-lock.json found; installing current plugin versions."
      run_nvim_headless '+Lazy! sync'
    fi
  fi

  info "Validating a clean headless startup"
  if ! run_nvim_headless "+lua assert(vim.fn.has('nvim') == 1)"; then
    restore_backup
    die "Updated configuration failed validation; previous state restored."
  fi

  UPDATE_ACTIVE=0

  if [[ "$KEEP_BACKUP" -eq 0 ]]; then
    rm -rf -- "$BACKUP_DIR"
  else
    info "Backup kept at: $BACKUP_DIR"
  fi

  printf '\nUpdate complete: %s -> %s\n' "$old_head" "$new_head"
  if [[ "$old_head" == "$new_head" ]]; then
    printf 'Repository was already current.\n'
  fi
}

main "$@"
