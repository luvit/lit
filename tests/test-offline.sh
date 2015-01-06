#!/bin/sh

BASE=`pwd`/test-offline
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG
cat $LIT_CONFIG
export LUVI_APP=`pwd`/app
luvit auth creationix || exit -1
luvit down || exit -1

for file in app/modules/creationix/*
do
  luvit add $file || exit -1
done

mkdir $APP_DIR
cp app/package.lua $APP_DIR
cd $APP_DIR
luvit install || exit -1
