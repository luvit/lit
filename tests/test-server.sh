#!/bin/sh
set -eu
LIT=`pwd`/lit
BASE=`pwd`/test-server
export LIT_CONFIG=$BASE/config
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`
$LIT down
$LIT serve
