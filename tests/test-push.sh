#!/bin/sh

LIT=`pwd`/lit
BASE=`pwd`/test-push
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`/app
$LIT auth creationix || exit -1
$LIT up ws://localhost:4822 || exit -1

$LIT publish app/modules/creationix/readline.lua || exit -1

for file in app/modules/creationix/*
do
  if [ $file != app/modules/creationix/readline.lua ]
    then $LIT publish $file || exit -1
  fi
done
