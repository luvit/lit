#!/bin/sh
systemctl stop lit
LUVI_APP=.: LUVI_TARGET=/usr/local/bin/lit luvit
systemctl start lit
