#!/bin/sh
set -eu
LUVI_VERSION=${LUVI_VERSION:-2.15.0}
LIT_VERSION=${LIT_VERSION:-3.9.0}

LUVI_OS=$(uname -s)
LUVI_ARCH=$(uname -m)

# 2.15.0 or higher uses a different URL
if [ "2.15.0" = "$(printf '%s\n%s\n' "2.15.0" "$LUVI_VERSION" | sort -V | head -n 1)" ]; then
	LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-${LUVI_OS}-${LUVI_ARCH}-luajit-regular"
else
	LUVI_URL="https://github.com/luvit/luvi/releases/download/v$LUVI_VERSION/luvi-regular-${LUVI_OS}_$LUVI_ARCH"
fi

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
