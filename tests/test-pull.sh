#!/bin/sh
set -eu
LIT=`pwd`/lit
BASE=`pwd`/test-pull
export LIT_CONFIG=$BASE/config
APP_DIR=$BASE/app
rm -rf $BASE
mkdir $BASE
echo "database: $BASE/db.git" > $LIT_CONFIG
echo "storage: git" >> $LIT_CONFIG

export LUVI_APP=`pwd`
$LIT auth creationix
$LIT up ws://localhost:4822

mkdir $APP_DIR
cp package.lua $APP_DIR
cd $APP_DIR
$LIT install
cd -

APP_DIR=$BASE/app2

mkdir $APP_DIR
cp package.lua $APP_DIR
cd $APP_DIR
$LIT install
cd -

$LIT down

APP_DIR=$BASE/app3

mkdir $APP_DIR
cp package.lua $APP_DIR
cd $APP_DIR
$LIT install
cd -

$LIT up

APP_DIR=$BASE/app4
mkdir $APP_DIR
cd $APP_DIR
$LIT make lit://luvit/lit
$LIT install luvit/lit
