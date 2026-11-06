#!/bin/sh
# install.sh: installs the `contentspiel` command.
#
#   curl -fsSL https://github.com/dominikknafelj/ContentSpiel/releases/latest/download/install.sh | sh
#
# It checks that Docker works, downloads the `contentspiel` wrapper from the
# latest release into ~/.local/bin and makes it executable. No sudo, nothing
# else is touched.
#
# CONTENTSPIEL_BIN_DIR        where to install (default ~/.local/bin)
# CONTENTSPIEL_WRAPPER_URL    where to download the wrapper from
set -eu

BIN_DIR=${CONTENTSPIEL_BIN_DIR:-$HOME/.local/bin}
# A quoted "~/..." arrives unexpanded; expand a leading ~/ ourselves.
# shellcheck disable=SC2088
# (the literal text "~/" is what is matched)
case $BIN_DIR in
  "~/"*) BIN_DIR=$HOME/${BIN_DIR#"~/"} ;;
esac
URL=${CONTENTSPIEL_WRAPPER_URL:-https://github.com/dominikknafelj/ContentSpiel/releases/latest/download/contentspiel}

if ! docker version >/dev/null 2>&1; then
  echo "Docker is not installed or not running. Install and start Docker, then run this again." >&2
  exit 1
fi

mkdir -p "$BIN_DIR"

# Download beside the target, move into place only when it is whole, so a
# failed download leaves nothing (and no half-written command) behind.
tmp=$(mktemp "$BIN_DIR/.contentspiel.XXXXXX")
trap 'rm -f "$tmp"' EXIT
trap 'exit 130' INT TERM
curl -fsSL -o "$tmp" "$URL"
chmod +x "$tmp"
mv "$tmp" "$BIN_DIR/contentspiel"
trap - EXIT INT TERM

echo "Installed $BIN_DIR/contentspiel"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on your PATH. Add it with:"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
    echo "and put that line in your shell's startup file (~/.zshrc or ~/.bashrc)."
    ;;
esac
