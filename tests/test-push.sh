#!/bin/sh

BASE=`pwd`/test-push
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`:
luvit auth creationix || exit -1
luvit up localhost || exit -1

for file in modules/creationix/*
do
  luvit add $file || exit -1
  luvit publish $file || exit -1
done
