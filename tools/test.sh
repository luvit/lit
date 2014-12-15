#!/bin/sh

# Make sure to use the dev version of lit
export LUVI_APP=`pwd`:`pwd`/../luvit/app

rm -rf ~/.lit* test-app

luvi auth creationix

for file in modules/creationix/*.lua
do
  luvi add $file || exit -1
done

mkdir test-app
cp package.lua test-app
cd test-app
luvi install
