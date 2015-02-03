#!/bin/sh

tests/test-offline.sh
tests/test-server.sh &
SERVER_PID=$!
tests/test-push.sh
tests/test-pull.sh
kill $SERVER_PID
