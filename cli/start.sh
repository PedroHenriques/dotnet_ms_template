#!/bin/sh
set -e;

sh ./cli/build.sh $1;
docker compose -f setup/local/docker-compose.yml -p myapp up --no-build $1;