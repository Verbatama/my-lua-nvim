Universal Neovim installer — Verbatama

Repository configuration:

https://github.com/Verbatama/my-lua-nvim.git

The Neovim configuration is stored at the repository root (init.lua, lua/, and lazy-lock.json).

Files

install.sh installs the latest stable Neovim, clones Verbatama/my-lua-nvim, activates it as ~/.config/nvim, bootstraps lazy.nvim, restores locked plugins, validates startup, and backs up replaced files.

update.sh detects either a direct ~/.config/nvim Git checkout or the managed symlink layout created by install.sh, fetches/rebases the repository, preserves local changes, restores locked plugins, validates startup, and rolls back on failure.

Install directly from Raw GitHub

curl -fsSL https://raw.githubusercontent.com/Verbatama/my-lua-nvim/main/install.sh | bash

Using wget:

wget -qO- https://raw.githubusercontent.com/Verbatama/my-lua-nvim/main/install.sh | bash

Safer download-and-review method:

tmpfile="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/Verbatama/my-lua-nvim/main/install.sh -o "$tmpfile"
less "$tmpfile"
bash "$tmpfile"
rm -f "$tmpfile"

Force a source build:

tmpfile="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/Verbatama/my-lua-nvim/main/install.sh -o "$tmpfile"
bash "$tmpfile" --source
rm -f "$tmpfile"

Update directly from Raw GitHub

curl -fsSL https://raw.githubusercontent.com/Verbatama/my-lua-nvim/main/update.sh | bash

Or from the local repository:

cd ~/.config/nvim
./update.sh

Update plugins beyond the committed lock file:

./update.sh --latest-plugins

The default update mode uses lazy-lock.json for reproducible plugin versions.

Publish corrected scripts

Place install.sh, update.sh, and this README.md in the root of my-lua-nvim, then run:

chmod +x install.sh update.sh
git add install.sh update.sh README.md
git commit -m "fix installer and updater repository paths"
git push origin main
