#!/bin/sh
set -eu
LUVI_VERSION=0.7.1
LIT_VERSION=0.10.5

LUVI_ARCH=static-`uname -s`_`uname -m`
if uname -m | grep arm; then
  LUVI_ARCH=large-`uname -s`_`uname -m`
fi
echo $LUVI_ARCH
LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-$LUVI_ARCH"
LIT_URL="https://github.com/luvit/lit/archive/$LIT_VERSION.zip"

# Download Files
echo "Downloading $LUVI_URL to luvi"
curl -L $LUVI_URL > luvi
chmod +x luvi
echo "Downloading $LIT_URL to lit.zip"
curl -L $LIT_URL > lit.zip

# Create lit using lit
LUVI_APP=lit.zip ./luvi make lit.zip

# Cleanup
rm lit.zip luvi
