#!/usr/bin/env bash
# Build the strid CLI in release mode and install it on PATH.
#
#   scripts/install-cli.sh            # installs to /usr/local/bin (or ~/.local/bin if not writable)
#   scripts/install-cli.sh ~/bin      # custom prefix directory
#   scripts/install-cli.sh --uninstall
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="$repo/ios/StridKit"
name="strid"

if [[ "${1:-}" == "--uninstall" ]]; then
  for d in /usr/local/bin /opt/homebrew/bin "$HOME/.local/bin" "$HOME/bin"; do
    if [[ -e "$d/$name" ]]; then rm -f "$d/$name" && echo "removed $d/$name"; fi
  done
  exit 0
fi

command -v swift >/dev/null || { echo "swift not found. Install Xcode or the Command Line Tools first." >&2; exit 1; }

# Pick an install dir: argument > /usr/local/bin if writable > ~/.local/bin
if [[ -n "${1:-}" ]]; then
  dest="$1"
elif [[ -w /usr/local/bin ]]; then
  dest=/usr/local/bin
else
  dest="$HOME/.local/bin"
fi
mkdir -p "$dest"

echo "Building $name (release)..."
swift build -c release --product "$name" --package-path "$pkg"
bin="$(swift build -c release --product "$name" --package-path "$pkg" --show-bin-path)/$name"

install -m 755 "$bin" "$dest/$name"
echo "Installed $dest/$name"

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Note: $dest is not on your PATH. Add it, e.g.:"
     echo "  fish:  fish_add_path $dest"
     echo "  zsh:   echo 'export PATH=\"$dest:\$PATH\"' >> ~/.zshrc" ;;
esac

"$dest/$name" --help | head -3
