#!/bin/sh

BASE=`pwd`/test-server
export LUVI_APP=`pwd`:
export LIT_CONFIG=$BASE/config
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git\nstorage: git" > $LIT_CONFIG

luvit auth creationix

for file in modules/creationix/*.lua
do
  luvit add $file || exit -1
done

luvit serve
