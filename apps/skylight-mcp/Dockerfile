# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Both bases are Alpine 3.24.3. The musl node binary from NODE_IMAGE is copied
# into PROXY_IMAGE so the runtime does not apt/apk-install an unpinned node.
# The references are build-args from docker-bake.hcl, which is the only pin.
ARG NODE_IMAGE
ARG PROXY_IMAGE

FROM ${NODE_IMAGE} AS build

ARG UPSTREAM_REF=5f22579d18a09cc4120401aca1f5f4deb5fe3915
ARG SOURCE=https://github.com/chrischall/skylight-mcp.git

RUN apk add --no-cache git

WORKDIR /src
RUN git init -q . \
    && git remote add origin "${SOURCE}" \
    && git fetch -q --depth 1 origin "${UPSTREAM_REF}" \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${UPSTREAM_REF}"

# esbuild's install script selects the musl binary used by `npm run build`
# (tsc, then the bundle). The process that runs is tsc's dist/index.js.
# `@chrischall/mcp-utils` lists vitest as an optional peer, and npm 11 installs
# that peer (then vite and esbuild) even for `npm ci --omit=dev` /
# `npm prune --omit=dev`. The second install uses `--legacy-peer-deps` so the
# image keeps the production tree: mcp-utils, the MCP server SDK, dotenv, zod.
RUN npm ci --ignore-scripts=false \
    && npm run build \
    && npm ci --omit=dev --legacy-peer-deps --ignore-scripts \
    && rm -rf src tests test .git

FROM ${PROXY_IMAGE}

# ldd of this node build needs libstdc++, libgcc_s, and libatomic.
# libgcc_s.so.1 is a regular file; the other two are symlinks plus their targets.
COPY --from=build /usr/local/bin/node /usr/local/bin/node
COPY --from=build /usr/lib/libstdc++.so.6* /usr/lib/libgcc_s.so.1 /usr/lib/libatomic.so.1* /usr/lib/
COPY --from=build --chown=0:0 /src /opt/skylight-mcp

RUN node --version

USER 10001:10001
WORKDIR /opt/skylight-mcp

# ENTRYPOINT inherited from mcp-proxy: catatonit -- mcp-proxy
# Cluster manifests replace this command to add --allowed-host and --env.
CMD ["--host", "0.0.0.0", "--port", "8080", "--", "node", "/opt/skylight-mcp/dist/index.js"]
