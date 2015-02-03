# source this to create a lit alias that runs directly our of this dir in dev mode.
LUVI_BIN=`pwd`/luvi-binaries/`uname -s`_`uname -m`/luvi
alias lit-dev=LUVI_APP=`pwd`'/app '$LUVI_BIN
