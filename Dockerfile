ARG BUILDER_IMAGE

##
# STEP 1: Retrieve dependencies
##
FROM ${BUILDER_IMAGE} AS builder

ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV}

WORKDIR /opt/app
# This copies our app source code into the build container
COPY ./ ./lattice_observer 

# Install necessary system dependencies
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
  git \
  ca-certificates && \
  update-ca-certificates

# This step installs all the build tools we'll need
RUN mix local.rebar --force && \
  mix local.hex --force

WORKDIR /opt/app/lattice_observer
# FAILS HERE
RUN mix deps.get
RUN mix compile
