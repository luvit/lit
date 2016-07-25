#!/bin/sh
set -eu
LIT=`pwd`/lit
BASE=`pwd`/test-push
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`
$LIT auth creationix
$LIT up ws://localhost:4822
$LIT claim luvit

$LIT publish deps/websocket-codec.lua
$LIT publish deps/weblit-*.lua
for file in deps/*
do
  $LIT publish $file
done
$LIT publish .
