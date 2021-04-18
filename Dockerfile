# From https://www.docker.com/blog/keep-nodejs-rockin-in-docker/, 
# thank you Bret Fisher.
FROM node:14-slim

ENV PORT 3000
# Misc tooling.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tree

VOLUME /usr/src/app/node_modules

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Copy project files.  See also .dockerignore.
COPY . .

EXPOSE 3000

# Running the app
ENTRYPOINT "/bin/bash"
