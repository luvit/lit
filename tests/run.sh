#!/bin/sh
set -eu
tests/test-offline.sh
tests/test-server.sh &
tests/test-push.sh
tests/test-pull.sh
killall lit
