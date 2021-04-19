#!/usr/bin/env bash

# Ensure container dependencies are synchronized.
docker-compose run --rm  --name=next-aronbeal-vercel-app-dev --service-ports --workdir=/usr/src/app app \
    /usr/local/bin/yarn install --check-files --unsafe-perm --frozen-lockfile

# Fail script after this point if errors.
set -e
# Run the container as interactive
docker-compose run --rm  --name=next-aronbeal-vercel-app-dev --service-ports app
