#!/bin/sh
set -eu
LUVI_VERSION=${LUVI_VERSION:-2.15.0}
LIT_VERSION=${LIT_VERSION:-3.9.0}

LUVI_ARCH=`uname -s`-`uname -m`
LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-$LUVI_ARCH-luajit-regular"
LIT_URL="https://lit.luvit.io/packages/luvit/lit/v$LIT_VERSION.zip"

# Download Files
echo "Downloading $LUVI_URL to luvi"
curl -L -f -o luvi $LUVI_URL
chmod +x luvi

echo "Downloading $LIT_URL to lit.zip"
curl -L -f -o lit.zip $LIT_URL

# Create lit using lit
./luvi lit.zip -- make lit.zip lit luvi
# Cleanup
rm -f lit.zip
# Create luvit using lit
./lit make lit://luvit/luvit luvit luvi
