#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "This script uses functionality which requires root privileges"
    exit 1
fi

# Start the build with an empty ACI
acbuild --debug begin

# In the event of the script exiting, end the build
acbuildEnd() {
    export EXIT=$?
    acbuild --debug end && exit $EXIT
}
trap acbuildEnd EXIT

# Name the ACI
acbuild --debug set-name luvit.io/lit-dev

# Based on alpine
acbuild --debug dep add quay.io/coreos/alpine-sh

# Install build tools
acbuild --debug run apk update
acbuild --debug run apk add cmake git build-base curl perl

# Clone luvi
acbuild --debug run -- \
  git clone --recursive https://github.com/luvit/luvi.git /luvi

# Build luvi
acbuild --debug run -- \
  make -C /luvi regular test

# Build lit
acbuild --debug run -- \
  curl https://lit.luvit.io/packages/luvit/lit/latest.zip -O
acbuild --debug run -- \
  /luvi/build/luvi latest.zip -- make latest.zip lit /luvi/build/luvi

# Test lit
acbuild --debug run -- /lit -v

# Extract luvi and lit
cp ./.acbuild/currentaci/rootfs/luvi/build/luvi \
   ./.acbuild/currentaci/rootfs/lit ./

# Save the aci
acbuild --debug write --overwrite luvi-dev.aci

# We're done with the build container
acbuild --debug end

# Start another build with an empty ACI
acbuild --debug begin

# Name the ACI
acbuild --debug set-name luvit.io/lit

# Based on alpine
acbuild --debug dep add quay.io/coreos/alpine-sh

# Install gcc runtime required by binary
# acbuild --debug run -- apk add libgcc

# Copy binaries into new container
acbuild --debug copy lit /usr/bin
acbuild --debug copy luvi /usr/bin

# Setup runtime envirnoment
# RUN mkdir /app
acbuild --debug set-working-directory /app
acbuild --debug set-exec -- /usr/bin/luvi /app --

# Save the ACI
acbuild --debug write --overwrite lit.aci
