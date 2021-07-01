#!/bin/sh
set -e

echo "Building latest luvi for latest alpine using docker container..."
docker build -t build-luvi build-luvi

echo "Extracting luvi binary..."
CONTAINER=$(docker create build-luvi)
docker cp $CONTAINER:/luvi/build/luvi build-lit/luvi
docker rm $CONTAINER

echo "Building lit using concatenation in host..."
cp build-lit/luvi build-lit/lit
curl -L https://lit.luvit.io/packages/luvit/lit/latest.zip >> build-lit/lit

echo "Making customized alpine image..."
docker build -t creationix/lit build-lit

echo "Run a test app..."
docker build test-app -t test-app
docker run --rm -it -p 8080:8080 test-app

echo "Done. Uploading to docker hub..."
docker push creationix/lit:alpine
