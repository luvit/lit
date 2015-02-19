#!/bin/sh
# Set versions
LUVI_VERSION=v0.7.0
LIT_VERSION=0.9.4

# Download luvi binary
LUVI_URL=https://github.com/luvit/luvi/releases/download/$LUVI_VERSION/luvi-static-`uname -s`_`uname -m`
curl -L $LUVI_URL > luvi
chmod +x luvi

# Download lit source and build self
LIT_ZIP=https://github.com/luvit/lit/archive/$LIT_VERSION.tar.gz
curl -L $LIT_ZIP | tar -xzvf -
BASE=lit-$LIT_VERSION
LIT_CONFIG=$BASE/litconfig
echo "database: $BASE/litdb.git" > $LIT_CONFIG
LIT_CONFIG=$LIT_CONFIG LUVI_APP=$BASE ./luvi make $BASE
