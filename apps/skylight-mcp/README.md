# skylight-mcp

Container image for [skylight-mcp](https://github.com/chrischall/skylight-mcp)
v1.4.7 (`5f22579d18a09cc4120401aca1f5f4deb5fe3915`). Upstream publishes source
and an npm package, not an image. This image builds that commit and serves it
over Streamable HTTP with
[mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) v0.13.3.

```text
ghcr.io/jtcressy-home/skylight-mcp
```

Pin downstream manifests by the release index digest, not by `rolling`:

```text
ghcr.io/jtcressy-home/skylight-mcp:1.4.7@sha256:<index digest>
```

## Build

`docker-bake.hcl` is the image contract.

| Input | Pin |
| --- | --- |
| `VERSION` | `1.4.7` |
| `UPSTREAM_REF` | `5f22579d18a09cc4120401aca1f5f4deb5fe3915` |
| Node | `NODE_IMAGE` in `docker-bake.hcl` |
| Bridge | `PROXY_IMAGE` in `docker-bake.hcl` |

Both bases are Alpine 3.24.3. The build fetches that exact commit, runs
`npm ci` and `npm run build`, then installs production dependencies only.
`npm prune --omit=dev` does not do that here: `@chrischall/mcp-utils` declares
vitest as an optional peer, and npm 11 installs that peer (and then vite and
esbuild) for a production install. The production install uses
`--legacy-peer-deps`, which leaves mcp-utils, the MCP server SDK, dotenv
18.0.8, and zod. The final stage is the mcp-proxy image plus the Node 26.13.0
musl binary (and the `libstdc++`, `libgcc_s`, and `libatomic` libraries that
binary links) and `/opt/skylight-mcp` with `dist/index.js` and those
production `node_modules`.
The image runs as uid `10001` and keeps mcp-proxy's entrypoint,
`catatonit -- mcp-proxy`.

`npm run build` is `tsc &&` the esbuild bundle. esbuild's install script has
to run so that bundle step can find its musl binary. The process that is
actually started is `node /opt/skylight-mcp/dist/index.js` (the tsc output),
not `dist/bundle.js`.

## Why upstream bumps are manual

`.renovaterc.json5` has a repo-wide rule that automerges changes to
`apps/**/docker-bake.hcl` after CI passes. That rule is copied from
`jtcressy/containers` so the layout stays compatible. With a Renovate
annotation on `UPSTREAM_REF`, an upstream commit would be merged and published
to the `rolling` tag without a review of the Skylight code.

`UPSTREAM_REF` therefore has **no** `# renovate:` annotation. Renovate will
not open a pull request to move it. Bumping past v1.4.7 is a manual pull
request, the same way `5f22579` was reviewed.

`NODE_IMAGE` and `PROXY_IMAGE` are the only copies of the base-image pins.
Renovate's digest manager reads those two `docker-bake.hcl` lines. The
Dockerfile args have no defaults, so a build takes the values from bake.

A later package rule sets `automerge: false` for `apps/skylight-mcp/**`.
Renovate applies rules in order, so this overrides the repo-wide automerge
for this app. Base-image digest bumps open pull requests and wait for a
person to merge them. Do not remove that rule, and do not add a datasource
annotation on `UPSTREAM_REF`, unless this policy changes on purpose.

## Runtime

The default command listens on `0.0.0.0:8080` and starts the stdio server:

```sh
catatonit -- mcp-proxy --host 0.0.0.0 --port 8080 -- node /opt/skylight-mcp/dist/index.js
```

Binding to `0.0.0.0` turns on mcp-proxy's DNS-rebinding check. Loopback hosts
are allowed. Any other Host header needs its own `--allowed-host`. The server
does not start a Skylight session until a tool is called, so `tools/list`
works with no credentials. Do not set `MCP_CONFIRM_MODE`. Do not put
`SKYLIGHT_EMAIL` or `SKYLIGHT_PASSWORD` in the image.

`/healthz` returns 204 and does not open an MCP session. BusyBox `wget` is in
the image for an exec probe of that URL.

## Smoke

`smoke.sh` checks node v26.13.0, mcp-proxy 0.13.3, uid 10001, BusyBox wget,
`/healthz` 204, and an MCP `initialize` plus `tools/list` (114 tools). It
passes no credentials. The server container is on a bridge with IP masquerade
disabled, so it has no route off the host. An internal network would also
drop the published port the check uses.
