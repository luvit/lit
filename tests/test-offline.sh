#!/bin/sh
set -eu
LIT=`pwd`/lit
BASE=`pwd`/test-offline
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG
cat $LIT_CONFIG
export LUVI_APP=`pwd`
$LIT auth creationix
$LIT down

for file in deps/*
do
  $LIT add $file
done

mkdir $APP_DIR
cp package.lua $APP_DIR
cd $APP_DIR
$LIT install
