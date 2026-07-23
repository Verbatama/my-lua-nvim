#!/usr/bin/env bash
# Safely update Verbatama's Neovim configuration and restore locked plugins.
# Supports both a direct ~/.config/nvim Git checkout and the managed symlink
# layout created by install.sh.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/Verbatama/my-lua-nvim.git}"
readonly REPO_BRANCH="${NVIM_CONFIG_BRANCH:-main}"
readonly CONFIG_SUBDIR="${NVIM_CONFIG_SUBDIR:-.}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly BIN_DIR="${NVIM_BIN_DIR:-$HOME/.local/bin}"
readonly CONFIG_DIR="${NVIM_CONFIG_DIR:-$XDG_CONFIG_HOME/nvim}"
readonly DEFAULT_REPO_DIR="$XDG_DATA_HOME/my-lua-nvim/repo"
readonly BACKUP_ROOT="${NVIM_BACKUP_DIR:-$XDG_DATA_HOME/my-lua-nvim/backups}"
readonly LAZY_DIR="$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
readonly LAZY_REPO="https://github.com/folke/lazy.nvim.git"
readonly LOCK_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/my-lua-nvim-update.lock"

LATEST_PLUGINS=0
SKIP_PLUGINS=0
KEEP_BACKUP=0
TMP_DIR=""
BACKUP_DIR=""
REPO_DIR=""
CONFIG_ROOT=""
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

Environment overrides:
  NVIM_CONFIG_REPO, NVIM_CONFIG_BRANCH, NVIM_CONFIG_SUBDIR
  NVIM_CONFIG_REPO_DIR, NVIM_CONFIG_DIR, NVIM_BIN_DIR, NVIM_BACKUP_DIR
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

is_git_worktree() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

validate_config_subdir() {
  case "$CONFIG_SUBDIR" in
    ''|.) return 0 ;;
    /*|..|../*|*/../*|*/..)
      die "NVIM_CONFIG_SUBDIR must be a relative path inside the repository."
      ;;
  esac
}

repo_config_path() {
  local repo=$1
  if [[ -z "$CONFIG_SUBDIR" || "$CONFIG_SUBDIR" == . ]]; then
    printf '%s\n' "$repo"
  else
    printf '%s/%s\n' "$repo" "$CONFIG_SUBDIR"
  fi
}

config_relative_path() {
  local name=$1
  if [[ -z "$CONFIG_SUBDIR" || "$CONFIG_SUBDIR" == . ]]; then
    printf '%s\n' "$name"
  else
    printf '%s/%s\n' "$CONFIG_SUBDIR" "$name"
  fi
}

physical_dir() {
  local path=$1
  [[ -d "$path" ]] || return 1
  (cd -P -- "$path" 2>/dev/null && pwd -P)
}

find_git_root() {
  local path root parent
  path="$(physical_dir "$1" || true)"
  [[ -n "$path" ]] || return 1
  while :; do
    if [[ -d "$path/.git" || -f "$path/.git" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
    [[ "$path" == / ]] && break
    parent="${path%/*}"
    [[ -n "$parent" ]] || parent=/
    [[ "$parent" != "$path" ]] || break
    path=$parent
  done
  return 1
}

normalize_git_url() {
  local url=${1%/}
  url=${url%.git}
  case "$url" in
    git@github.com:*) url="https://github.com/${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="https://github.com/${url#ssh://git@github.com/}" ;;
    http://github.com/*) url="https://github.com/${url#http://github.com/}" ;;
  esac
  case "$url" in
    https://github.com/*) printf '%s\n' "${url,,}" ;;
    *) printf '%s\n' "$url" ;;
  esac
}

origin_matches_expected() {
  local repo=$1 remote
  remote="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  [[ -n "$remote" ]] || return 1
  [[ "$(normalize_git_url "$remote")" == "$(normalize_git_url "$REPO_URL")" ]]
}

detect_repo_dir() {
  local candidate=""

  if [[ -n "${NVIM_CONFIG_REPO_DIR:-}" ]]; then
    printf '%s\n' "$NVIM_CONFIG_REPO_DIR"
    return 0
  fi

  candidate="$(find_git_root "$CONFIG_DIR" || true)"
  if [[ -n "$candidate" ]] && origin_matches_expected "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if is_git_worktree "$DEFAULT_REPO_DIR" && origin_matches_expected "$DEFAULT_REPO_DIR"; then
    printf '%s\n' "$DEFAULT_REPO_DIR"
    return 0
  fi

  if [[ -n "$candidate" ]]; then
    local actual_remote
    actual_remote="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
    die "Neovim config is a Git repository, but origin is unexpected: ${actual_remote:-<missing>}. Expected: $REPO_URL"
  fi

  printf '%s\n' "$DEFAULT_REPO_DIR"
}

same_directory() {
  local left right
  left="$(physical_dir "$1" || true)"
  right="$(physical_dir "$2" || true)"
  [[ -n "$left" && -n "$right" && "$left" == "$right" ]]
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

ensure_config_active() {
  CONFIG_ROOT="$(repo_config_path "$REPO_DIR")"
  [[ -f "$CONFIG_ROOT/init.lua" ]] || die "Repository does not contain init.lua at: $CONFIG_ROOT"

  if same_directory "$CONFIG_DIR" "$CONFIG_ROOT"; then
    return 0
  fi

  if [[ -e "$CONFIG_DIR" && ! -L "$CONFIG_DIR" ]]; then
    die "$CONFIG_DIR exists and is not the selected repository. Refusing to replace it during update."
  fi

  atomic_link "$CONFIG_ROOT" "$CONFIG_DIR"
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
  if [[ -x "$BIN_DIR/nvim" ]]; then nvim="$BIN_DIR/nvim"
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
  ensure_config_active
  if [[ "$SKIP_PLUGINS" -eq 0 && -f "$CONFIG_ROOT/lazy-lock.json" ]]; then
    run_nvim_headless '+Lazy! restore' || warn "Repository rollback succeeded, but plugin rollback needs manual attention."
  fi
}

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
  rm -rf -- "$LOCK_DIR" 2>/dev/null || true
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap on_error ERR
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock() {
  local pid_file="$LOCK_DIR/pid" old_pid=""
  mkdir -p "$(dirname "$LOCK_DIR")"

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    return 0
  fi

  if [[ -r "$pid_file" ]]; then
    read -r old_pid < "$pid_file" || true
  fi
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    die "Another update is already running with PID $old_pid."
  fi

  warn "Removing a stale update lock: $LOCK_DIR"
  rm -rf -- "$LOCK_DIR"
  mkdir "$LOCK_DIR" || die "Unable to acquire update lock: $LOCK_DIR"
  printf '%s\n' "$$" > "$pid_file"
}

update_repository() {
  local current_remote stash_created=0
  current_remote="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  [[ -n "$current_remote" ]] || die "The repository has no origin remote: $REPO_DIR"
  [[ "$(normalize_git_url "$current_remote")" == "$(normalize_git_url "$REPO_URL")" ]] || \
    die "Unexpected origin remote: $current_remote. Expected: $REPO_URL"

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

  CONFIG_ROOT="$(repo_config_path "$REPO_DIR")"
  [[ -f "$CONFIG_ROOT/init.lua" ]] || {
    restore_backup
    die "Updated repository does not contain init.lua at the configured path: $CONFIG_SUBDIR"
  }
}

main() {
  [[ -n "${HOME:-}" && "$HOME" != / ]] || die "HOME must point to a normal user home directory."
  validate_config_subdir
  have git || die "git is required."
  [[ "$(basename "$CONFIG_DIR")" == nvim ]] || die "NVIM_CONFIG_DIR must end with /nvim so Neovim can discover it through XDG_CONFIG_HOME."

  REPO_DIR="$(detect_repo_dir)"
  is_git_worktree "$REPO_DIR" || die "Config repository not found: $REPO_DIR. Run install.sh first."
  CONFIG_ROOT="$(repo_config_path "$REPO_DIR")"
  [[ -f "$CONFIG_ROOT/init.lua" ]] || die "Repository does not contain init.lua at: $CONFIG_ROOT"

  acquire_lock
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nvim-update.XXXXXXXX")"
  mkdir -p "$BACKUP_ROOT"
  BACKUP_DIR="$(mktemp -d "$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-update.XXXXXXXX")"

  local old_head new_head lock_path
  old_head="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
  update_repository
  new_head="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
  ensure_config_active

  if [[ "$SKIP_PLUGINS" -eq 0 ]]; then
    bootstrap_lazy
    if [[ "$LATEST_PLUGINS" -eq 1 ]]; then
      info "Updating plugins to latest revisions"
      run_nvim_headless '+Lazy! sync'
      lock_path="$(config_relative_path lazy-lock.json)"
      if [[ -n "$(git -C "$REPO_DIR" status --porcelain -- "$lock_path")" ]]; then
        warn "lazy-lock.json changed locally. Review and commit it to keep other machines reproducible."
      fi
    elif [[ -f "$CONFIG_ROOT/lazy-lock.json" ]]; then
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
  printf 'Repository: %s\n' "$REPO_DIR"
  if [[ "$old_head" == "$new_head" ]]; then
    printf 'Repository was already current.\n'
  fi
}

main "$@"

