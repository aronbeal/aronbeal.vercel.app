# From https://www.docker.com/blog/keep-nodejs-rockin-in-docker/, 
# thank you Bret Fisher.
FROM node:14-slim as base

ENV PORT 3000
# Misc tooling.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tree

# Create the directory and make it owned by node before declaring the volume,
# See https://devops.stackexchange.com/a/4542
RUN mkdir -p /usr/src/app/node_modules && chown -R node /usr/src/app
VOLUME [ "/usr/src/app/node_modules" ]
RUN chown -R node /usr/src/app/node_modules && chmod u+rwx /usr/src/app/node_modules

USER node
WORKDIR /usr/src/app
# First item here is for EACCESS issues with docker volumes and node
# when running as the non-root user.
RUN yarn global add vercel

EXPOSE 3000

# Running the app
ENTRYPOINT ["/bin/bash"]
