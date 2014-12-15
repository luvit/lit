#!/bin/sh

# Make sure to use the dev version of lit
export LUVI_APP=.:../luvit/app

rm -rf ~/.lit*

luvi auth creationix

for file in modules/creationix/*.lua
do
  luvi add $file || exit -1
done
