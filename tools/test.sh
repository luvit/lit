#!/bin/sh

# Make sure to use the dev version of lit
export LUVI_APP=`pwd`:

# rm -rf ~/.lit* test-app

luvit auth creationix

for file in modules/creationix/*.lua
do
  luvit add $file || exit -1
done

mkdir test-app
cp package.lua test-app
cd test-app
luvit install
