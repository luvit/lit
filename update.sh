#!/bin/sh
systemctl stop lit
LUVI_APP=`pwd`/app LUVI_TARGET=/usr/local/bin/lit /usr/local/bin/luvit
systemctl start lit
