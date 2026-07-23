#!/usr/bin/env bash
# Universal user-local Neovim installer for Linux.
# Main path: official Neovim release tarball (x86_64/arm64 + glibc).
# Fallback: build the stable branch from source for musl/other architectures.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly SCRIPT_NAME="${0##*/}"
readonly ORIGINAL_PATH="$PATH"
readonly REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/Verbatama/my-lua-nvim.git}"
readonly REPO_BRANCH="${NVIM_CONFIG_BRANCH:-main}"
readonly CONFIG_SUBDIR="${NVIM_CONFIG_SUBDIR:-.}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly INSTALL_ROOT="${NVIM_INSTALL_ROOT:-$HOME/.local/opt/neovim}"
readonly BIN_DIR="${NVIM_BIN_DIR:-$HOME/.local/bin}"
readonly CONFIG_DIR="${NVIM_CONFIG_DIR:-$XDG_CONFIG_HOME/nvim}"
readonly REPO_DIR="${NVIM_CONFIG_REPO_DIR:-$XDG_DATA_HOME/my-lua-nvim/repo}"
readonly BACKUP_ROOT="${NVIM_BACKUP_DIR:-$XDG_DATA_HOME/my-lua-nvim/backups}"
readonly LAZY_DIR="$XDG_DATA_HOME/nvim/lazy/lazy.nvim"
readonly RELEASE_API="https://api.github.com/repos/neovim/neovim/releases/latest"
readonly NEOVIM_REPO="https://github.com/neovim/neovim.git"
readonly LAZY_REPO="https://github.com/folke/lazy.nvim.git"

FORCE_SOURCE=0
SKIP_DEPS=0
SKIP_PLUGINS=0
KEEP_TEMP=0
TMP_DIR=""
BACKUP_DIR=""

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --source         Force building Neovim stable from source.
  --skip-deps      Do not install missing OS packages automatically.
  --skip-plugins   Install Neovim and config without restoring plugins.
  --keep-temp      Keep the temporary directory for debugging.
  -h, --help       Show this help.

Environment overrides:
  NVIM_CONFIG_REPO, NVIM_CONFIG_BRANCH, NVIM_CONFIG_SUBDIR
  NVIM_INSTALL_ROOT, NVIM_BIN_DIR, NVIM_CONFIG_DIR
  NVIM_CONFIG_REPO_DIR, NVIM_BACKUP_DIR
USAGE
}

while (($#)); do
  case "$1" in
    --source) FORCE_SOURCE=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --skip-plugins) SKIP_PLUGINS=1 ;;
    --keep-temp) KEEP_TEMP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
  printf 'ERROR: this installer is for Linux only.\n' >&2
  exit 1
fi

if [[ -t 1 ]]; then
  C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_RESET=''
fi

info() { printf '%s==>%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

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

cleanup() {
  local status=$?
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" && "$KEEP_TEMP" -eq 0 ]]; then
    rm -rf -- "$TMP_DIR"
  elif [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    warn "Temporary directory kept at: $TMP_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif have sudo; then
    sudo -- "$@"
  elif have doas; then
    doas -- "$@"
  else
    die "Root access is required to install missing dependencies. Install them manually or rerun with --skip-deps after doing so."
  fi
}

detect_package_manager() {
  local pm
  for pm in apt-get dnf5 dnf yum microdnf pacman zypper apk xbps-install eopkg emerge urpmi slackpkg swupd; do
    if have "$pm"; then printf '%s\n' "$pm"; return 0; fi
  done
  if have nix; then printf '%s\n' nix; return 0; fi
  if have guix; then printf '%s\n' guix; return 0; fi
  return 1
}

install_base_dependencies() {
  [[ "$SKIP_DEPS" -eq 0 ]] || return 1
  local pm
  pm="$(detect_package_manager || true)"
  [[ -n "$pm" ]] || die "No supported package manager found. Required tools: git, curl or wget, tar, gzip, ca-certificates."
  info "Installing base dependencies with $pm"
  case "$pm" in
    apt-get)
      as_root apt-get update
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates tar gzip
      ;;
    dnf5|dnf|yum|microdnf)
      as_root "$pm" install -y git curl ca-certificates tar gzip
      ;;
    pacman)
      as_root pacman -Sy --needed --noconfirm git curl ca-certificates tar gzip
      ;;
    zypper)
      as_root zypper --non-interactive install git curl ca-certificates tar gzip
      ;;
    apk)
      as_root apk add --no-cache git curl ca-certificates tar gzip
      ;;
    xbps-install)
      as_root xbps-install -Sy git curl ca-certificates tar gzip
      ;;
    eopkg)
      as_root eopkg install -y git curl ca-certs tar gzip
      ;;
    emerge)
      as_root emerge --noreplace dev-vcs/git net-misc/curl app-misc/ca-certificates app-arch/tar app-arch/gzip
      ;;
    urpmi)
      as_root urpmi --auto git curl ca-certificates tar gzip
      ;;
    slackpkg)
      as_root slackpkg -batch=on -default_answer=y install git curl ca-certificates tar gzip
      ;;
    swupd)
      as_root swupd bundle-add git network-basic os-core-dev
      ;;
    nix)
      nix profile install 'nixpkgs#git' 'nixpkgs#curl' 'nixpkgs#gnutar' 'nixpkgs#gzip' || \
        nix-env -iA nixpkgs.git nixpkgs.curl nixpkgs.gnutar nixpkgs.gzip
      ;;
    guix)
      guix install git curl tar gzip nss-certs
      ;;
  esac
  hash -r
}

missing_base_tools() {
  local missing=()
  have git || missing+=(git)
  have tar || missing+=(tar)
  if ! have curl && ! have wget && ! have busybox && ! have python3 && ! have python; then
    missing+=("curl-or-wget")
  fi
  ((${#missing[@]} == 0)) || printf '%s\n' "${missing[*]}"
}

ensure_base_tools() {
  local missing
  missing="$(missing_base_tools || true)"
  if [[ -n "$missing" ]]; then
    warn "Missing base tools: $missing"
    install_base_dependencies
    missing="$(missing_base_tools || true)"
    [[ -z "$missing" ]] || die "Still missing required tools: $missing"
  fi
}

download() {
  local url=$1 output=$2
  if have curl; then
    curl --fail --location --silent --show-error \
      --retry 4 --retry-delay 2 --connect-timeout 20 \
      --output "$output" "$url"
  elif have wget; then
    wget -q --tries=4 --timeout=20 -O "$output" "$url"
  elif have busybox; then
    busybox wget -q -O "$output" "$url"
  elif have python3; then
    python3 - "$url" "$output" <<'PY'
import sys, urllib.request
url, output = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=30) as response, open(output, "wb") as dst:
    dst.write(response.read())
PY
  elif have python; then
    python - "$url" "$output" <<'PY'
import sys, urllib.request
url, output = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=30) as response, open(output, "wb") as dst:
    dst.write(response.read())
PY
  else
    die "No downloader is available."
  fi
  [[ -s "$output" ]] || die "Downloaded file is empty: $url"
}

sha256_file() {
  local file=$1
  if have sha256sum; then sha256sum "$file" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$file" | awk '{print $1}'
  elif have openssl; then openssl dgst -sha256 "$file" | awk '{print $NF}'
  elif have busybox; then busybox sha256sum "$file" | awk '{print $1}'
  else return 1
  fi
}

parse_release_tag() {
  sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' "$1" | head -n1
}

parse_asset_digest() {
  local json=$1 asset=$2
  tr -d '\n' < "$json" \
    | sed 's/},{/}\n{/g' \
    | grep -F "\"name\":\"$asset\"" \
    | sed -n 's/.*"digest":"sha256:\([0-9a-fA-F]\{64\}\)".*/\1/p' \
    | head -n1 || true
}

libc_kind() {
  if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then printf 'glibc\n'; return; fi
  if [[ -e /etc/alpine-release ]] || compgen -G '/lib/ld-musl-*.so.1' >/dev/null; then printf 'musl\n'; return; fi
  local output
  output="$(ldd --version 2>&1 || true)"
  if grep -qi musl <<<"$output"; then printf 'musl\n';
  elif grep -qiE 'glibc|GNU libc' <<<"$output"; then printf 'glibc\n';
  else printf 'unknown\n'; fi
}

normalize_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) printf '%s\n' "$(uname -m)" ;;
  esac
}

backup_path() {
  local path=$1 label=$2
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$BACKUP_DIR"
    local target="$BACKUP_DIR/$label"
    local n=0
    while [[ -e "$target" || -L "$target" ]]; do n=$((n + 1)); target="$BACKUP_DIR/${label}.$n"; done
    mv -- "$path" "$target"
    info "Backup created: $target"
  fi
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

install_prebuilt_neovim() {
  local arch=$1
  local asset="nvim-linux-${arch}.tar.gz"
  local metadata="$TMP_DIR/release.json"
  local tag='stable' digest=''
  local archive="$TMP_DIR/$asset"

  info "Reading the latest stable Neovim release metadata"
  if download "$RELEASE_API" "$metadata"; then
    tag="$(parse_release_tag "$metadata")"
    [[ -n "$tag" ]] || tag='stable'
    digest="$(parse_asset_digest "$metadata" "$asset")"
  fi

  info "Downloading Neovim $tag for Linux $arch"
  download "https://github.com/neovim/neovim/releases/download/${tag}/${asset}" "$archive"

  if [[ -n "$digest" ]]; then
    local actual
    actual="$(sha256_file "$archive" || true)"
    [[ -n "$actual" ]] || die "Cannot verify SHA-256; install sha256sum, shasum, or openssl."
    [[ "${actual,,}" == "${digest,,}" ]] || die "SHA-256 verification failed for $asset."
    info "SHA-256 verified"
  else
    warn "GitHub did not provide a parsable asset digest; continuing with HTTPS transport verification only."
  fi

  local extract_dir="$TMP_DIR/extract"
  mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir"
  local candidate="$extract_dir/nvim-linux-$arch"
  [[ -x "$candidate/bin/nvim" ]] || die "Unexpected Neovim archive layout."

  if ! "$candidate/bin/nvim" --headless +'lua io.write(vim.version().major)' +qa >/dev/null 2>&1; then
    warn "Official prebuilt Neovim cannot run on this system; source build will be used."
    return 1
  fi

  backup_path "$INSTALL_ROOT" neovim-install
  mkdir -p "$(dirname "$INSTALL_ROOT")"
  mv -- "$candidate" "$INSTALL_ROOT"
  backup_path "$BIN_DIR/nvim" nvim-bin
  atomic_link "$INSTALL_ROOT/bin/nvim" "$BIN_DIR/nvim"
  return 0
}

install_build_dependencies() {
  local required=(git make cmake)
  local missing=() cmd
  for cmd in "${required[@]}"; do have "$cmd" || missing+=("$cmd"); done
  ((${#missing[@]} == 0)) && return 0
  [[ "$SKIP_DEPS" -eq 0 ]] || die "Source build requires: ${missing[*]}"

  local pm
  pm="$(detect_package_manager || true)"
  [[ -n "$pm" ]] || die "No supported package manager found for source-build dependencies: ${missing[*]}"
  info "Installing source-build dependencies with $pm"
  case "$pm" in
    apt-get)
      as_root apt-get update
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ninja-build gettext cmake curl build-essential git
      ;;
    dnf5|dnf)
      as_root "$pm" install -y ninja-build cmake gcc gcc-c++ make gettext curl git glibc-gconv-extra
      ;;
    yum|microdnf)
      as_root "$pm" install -y ninja-build cmake gcc gcc-c++ make gettext curl git
      ;;
    pacman)
      as_root pacman -Sy --needed --noconfirm base-devel cmake ninja curl git
      ;;
    zypper)
      as_root zypper --non-interactive install ninja cmake gcc-c++ gettext-tools curl git
      ;;
    apk)
      as_root apk add --no-cache build-base cmake coreutils curl gettext-tiny-dev git linux-headers
      ;;
    xbps-install)
      as_root xbps-install -Sy base-devel cmake curl git ninja gettext
      ;;
    eopkg)
      as_root eopkg install -y -c system.devel cmake ninja gettext-devel curl git
      ;;
    emerge)
      as_root emerge --noreplace sys-devel/gcc dev-build/cmake dev-build/ninja sys-devel/gettext net-misc/curl dev-vcs/git
      ;;
    urpmi)
      as_root urpmi --auto task-c-devel cmake ninja-build gettext curl git
      ;;
    slackpkg)
      as_root slackpkg -batch=on -default_answer=y install gcc make cmake ninja gettext curl git
      ;;
    swupd)
      as_root swupd bundle-add c-basic dev-utils git network-basic
      ;;
    nix)
      die "On NixOS, use the Nix package fallback instead of a generic source build."
      ;;
    guix)
      guix install gcc-toolchain make cmake ninja gettext git curl
      ;;
  esac
  hash -r
  for cmd in git make cmake; do have "$cmd" || die "Required build command is still missing: $cmd"; done
}

install_with_nix_or_guix() {
  if have nix; then
    info "Installing Neovim through the Nix user profile"
    nix profile install 'nixpkgs#neovim' || nix-env -iA nixpkgs.neovim
    hash -r
    local candidate="${HOME}/.nix-profile/bin/nvim"
    [[ -x "$candidate" ]] || candidate="$(command -v nvim || true)"
    [[ -x "$candidate" ]] || return 1
    backup_path "$BIN_DIR/nvim" nvim-bin
    atomic_link "$candidate" "$BIN_DIR/nvim"
    return 0
  fi
  if have guix; then
    info "Installing Neovim through the Guix user profile"
    guix install neovim
    hash -r
    local candidate="${HOME}/.guix-profile/bin/nvim"
    [[ -x "$candidate" ]] || candidate="$(command -v nvim || true)"
    [[ -x "$candidate" ]] || return 1
    backup_path "$BIN_DIR/nvim" nvim-bin
    atomic_link "$candidate" "$BIN_DIR/nvim"
    return 0
  fi
  return 1
}

build_neovim_from_source() {
  if [[ -e /etc/NIXOS ]] && install_with_nix_or_guix; then return 0; fi
  install_build_dependencies
  local src="$TMP_DIR/neovim-src" staging="$TMP_DIR/neovim-staging"
  info "Cloning the Neovim stable source"
  git clone --depth 1 --branch stable "$NEOVIM_REPO" "$src"
  info "Building Neovim stable from source"
  make -C "$src" CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="$staging" install
  [[ -x "$staging/bin/nvim" ]] || die "Source build completed without producing nvim."
  "$staging/bin/nvim" --version >/dev/null
  backup_path "$INSTALL_ROOT" neovim-install
  mkdir -p "$(dirname "$INSTALL_ROOT")"
  mv -- "$staging" "$INSTALL_ROOT"
  backup_path "$BIN_DIR/nvim" nvim-bin
  atomic_link "$INSTALL_ROOT/bin/nvim" "$BIN_DIR/nvim"
}

install_neovim() {
  mkdir -p "$BIN_DIR"
  local arch libc
  arch="$(normalize_arch)"
  libc="$(libc_kind)"
  info "Detected architecture=$arch, libc=$libc"

  if [[ "$FORCE_SOURCE" -eq 0 && "$libc" == glibc && ("$arch" == x86_64 || "$arch" == arm64) ]]; then
    install_prebuilt_neovim "$arch" && return 0
  fi

  if [[ "$libc" == unknown ]] && [[ "$FORCE_SOURCE" -eq 0 ]] && [[ "$arch" == x86_64 || "$arch" == arm64 ]]; then
    install_prebuilt_neovim "$arch" && return 0
  fi

  build_neovim_from_source
}

bootstrap_lazy() {
  if [[ -d "$LAZY_DIR/.git" ]]; then return 0; fi
  if [[ -e "$LAZY_DIR" || -L "$LAZY_DIR" ]]; then backup_path "$LAZY_DIR" lazy.nvim; fi
  mkdir -p "$(dirname "$LAZY_DIR")"
  info "Bootstrapping lazy.nvim"
  git clone --filter=blob:none --branch stable "$LAZY_REPO" "$LAZY_DIR"
}

run_nvim_headless() {
  local config_home=$1 command=$2
  local nvim="$BIN_DIR/nvim"
  [[ -x "$nvim" ]] || die "Installed Neovim is not executable: $nvim"
  if have timeout; then
    XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
      timeout 20m "$nvim" --headless "$command" +qa
  else
    XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
      "$nvim" --headless "$command" +qa
  fi
}

install_config() {
  local staged_repo="$TMP_DIR/config-repo"
  local staged_config
  local final_config
  local test_config_home="$TMP_DIR/config-home"

  info "Cloning Neovim config from $REPO_URL ($REPO_BRANCH)"
  git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$staged_repo"
  staged_config="$(repo_config_path "$staged_repo")"
  [[ -f "$staged_config/init.lua" ]] || \
    die "Repository does not contain init.lua at the configured path: $CONFIG_SUBDIR"

  bootstrap_lazy
  mkdir -p "$test_config_home"
  ln -s "$staged_config" "$test_config_home/nvim"

  if [[ "$SKIP_PLUGINS" -eq 0 ]]; then
    if [[ -f "$staged_config/lazy-lock.json" ]]; then
      info "Restoring plugins exactly from lazy-lock.json"
      run_nvim_headless "$test_config_home" '+Lazy! restore'
    else
      warn "No lazy-lock.json found; installing current plugin versions."
      run_nvim_headless "$test_config_home" '+Lazy! sync'
    fi
  fi

  info "Validating a clean headless startup"
  run_nvim_headless "$test_config_home" "+lua assert(vim.fn.has('nvim') == 1)"

  backup_path "$REPO_DIR" config-repository
  mkdir -p "$(dirname "$REPO_DIR")"
  mv -- "$staged_repo" "$REPO_DIR"
  final_config="$(repo_config_path "$REPO_DIR")"

  backup_path "$CONFIG_DIR" nvim-config
  mkdir -p "$(dirname "$CONFIG_DIR")"
  atomic_link "$final_config" "$CONFIG_DIR"
}

main() {
  [[ -n "${HOME:-}" && "$HOME" != / ]] || die "HOME must point to a normal user home directory."
  validate_config_subdir
  [[ "$(basename "$CONFIG_DIR")" == nvim ]] || die "NVIM_CONFIG_DIR must end with /nvim so Neovim can discover it through XDG_CONFIG_HOME."
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nvim-install.XXXXXXXX")"
  BACKUP_DIR="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)"

  ensure_base_tools
  install_neovim
  export PATH="$BIN_DIR:$PATH"
  hash -r
  install_config

  local version
  version="$($BIN_DIR/nvim --version | head -n1)"
  printf '\n%sInstallation complete.%s\n' "$C_BOLD" "$C_RESET"
  printf '  Neovim : %s\n' "$version"
  printf '  Binary : %s\n' "$BIN_DIR/nvim"
  printf '  Config : %s -> %s\n' "$CONFIG_DIR" "$(repo_config_path "$REPO_DIR")"
  [[ -d "$BACKUP_DIR" ]] && printf '  Backup : %s\n' "$BACKUP_DIR"
  if [[ ":$ORIGINAL_PATH:" != *":$BIN_DIR:"* ]]; then
    printf '\nAdd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$BIN_DIR"
  fi
}

main "$@"

