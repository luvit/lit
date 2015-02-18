#!/bin/sh

LIT=`pwd`/lit
BASE=`pwd`/test-push
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`
$LIT auth creationix || exit -1
$LIT up ws://localhost:4822 || exit -1

for file in modules/*
do
  $LIT publish $file || exit -1
done
