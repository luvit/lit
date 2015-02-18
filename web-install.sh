#!/bin/sh
# Set versions
LUVI_VERSION=0.6.6
LIT_VERSION=0.9.1

# Download luvi binary
LUVI_URL=https://github.com/luvit/luvi-binaries/raw/v$LUVI_VERSION/`uname -s`_`uname -m`/luvi
curl -L $LUVI_URL > luvi
chmod +x luvi

# Download lit source and build self
LIT_ZIP=https://github.com/luvit/lit/archive/$LIT_VERSION.tar.gz
curl -L $LIT_ZIP | tar -xzv
BASE=lit-$LIT_VERSION
LIT_CONFIG=$BASE/litconfig
echo "database: $BASE/litdb.git" > $LIT_CONFIG
LIT_CONFIG=$LIT_CONFIG LUVI_APP=$BASE ./luvi make $BASE
