#!/bin/sh

BASE=`pwd`/test-online
export LUVI_APP=`pwd`:
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git\nstorage: git" > $LIT_CONFIG

luvit auth creationix
luvit up localhost

mkdir $APP_DIR
cp package.lua $APP_DIR
cd $APP_DIR
luvit install