#!/bin/sh
set -e

echo "Making customized alpine image..."
docker build -t creationix/lit lit-runtime

echo "Run a test app..."
docker build test-app -t test-app
docker run --rm -it -p 8080:8080 test-app

echo "Done. Uploading to docker hub..."
docker push creationix/lit
