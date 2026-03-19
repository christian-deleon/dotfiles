#!/bin/bash
# Install cloc via latest GitHub release
set -e

if command -v cloc &>/dev/null; then
    echo "cloc is already installed"
    exit 0
fi

VERSION="$(curl -fsSL https://api.github.com/repos/AlDanial/cloc/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
curl -fsSLo /tmp/cloc "https://github.com/AlDanial/cloc/releases/download/${VERSION}/cloc-${VERSION#v}.pl"
chmod +x /tmp/cloc
sudo install /tmp/cloc /usr/local/bin/cloc
rm -f /tmp/cloc
