#!/bin/sh
set -eu
LUVI_VERSION=2.5.2
LIT_VERSION=3.0.2

LUVI_ARCH=`uname -s`_`uname -m`
LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-regular-$LUVI_ARCH"
LIT_URL="https://lit.luvit.io/packages/luvit/lit/v$LIT_VERSION.zip"

# Download Files
echo "Downloading $LUVI_URL to luvi"
curl -L $LUVI_URL > luvi
chmod +x luvi
echo "Downloading $LIT_URL to lit.zip"
curl -L $LIT_URL > lit.zip

# Create lit using lit
./luvi lit.zip -- make lit.zip

# Cleanup
rm -f lit.zip
