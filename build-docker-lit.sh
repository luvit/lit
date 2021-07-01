#!/bin/sh
set -e
echo "Building latest luvi and lit for latest alpine using docker container..."
docker build -t lit:alpine-dev -f Dockerfile.alpine-dev .
echo "Extracting lit and luvi binaries..."
CONTAINER=$(docker create lit:alpine-dev)
docker cp $CONTAINER:/luvi/build/luvi luvi
docker cp $CONTAINER:/luvi/lit lit
docker rm $CONTAINER
echo "Making customized alpine image..."
docker build -t creationix/lit:alpine -f Dockerfile.alpine .
echo "Testing lit in new docker image"
docker run --rm creationix/lit:alpine lit -v
echo "Done. Uploading to docker hub..."
docker push creationix/lit:alpine
