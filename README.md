Universal Neovim installer

Files:

install.sh: installs the latest stable Neovim in the user's home directory, clones Verbatama/my-nvim-verbatama, links the repository's nvim/ directory to the XDG config path, bootstraps lazy.nvim, restores locked plugins, validates startup, and backs up replaced files.

update.sh: safely fetches/rebases the same repository, preserves local changes, restores locked plugins, validates startup, and rolls back on failure.

Install

chmod +x install.sh update.sh
./install.sh

Force a source build:

./install.sh --source
curl -fsSL https://raw.githubusercontent.com/Verbatama/my-nvim-verbatama/main/install.sh | bash
Update

./update.sh
curl -fsSL https://raw.githubusercontent.com/Verbatama/my-nvim-verbatama/main/update.sh | bash
Update plugins beyond the committed lock file:

./update.sh --latest-plugins

The default update mode uses lazy-lock.json for reproducible plugin versions.
