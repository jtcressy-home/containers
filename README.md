# Containers

Container image builds for jtcressy-home services and glue that do not have an
upstream image we want to consume directly.

Images are published to GitHub Container Registry under:

```text
ghcr.io/jtcressy-home/<app>
```

The directory layout matches
[jtcressy/containers](https://github.com/jtcressy/containers) so that repository
can be migrated into this one later. The registry namespace here is
`ghcr.io/jtcressy-home`. Workflows log in to GHCR with `GITHUB_TOKEN` and
`packages: write`. They do not use a personal access token.

## Images

| App | Image | Upstream |
| --- | --- | --- |
| `skylight-mcp` | `ghcr.io/jtcressy-home/skylight-mcp` | `chrischall/skylight-mcp` @ `5f22579` (v1.4.7) |

## Repository Pattern

Each image lives under `apps/<app>/` and owns its build inputs:

```text
apps/<app>/
  Dockerfile
  docker-bake.hcl
  README.md
  smoke.sh       # optional app-specific smoke check; receives the image ref
```

The `docker-bake.hcl` file is the image contract. It defines:

- `APP`: the GHCR package name.
- `VERSION`: the application version tag.
- `UPSTREAM_REF`: the pinned upstream commit or release reference.
- `SOURCE`: the upstream source repository.
- `image-local`: local single-platform build target.
- `image-all`: release multi-platform build target.

Renovate reads inline annotations in `docker-bake.hcl`. For upstreams without
tags or releases, use Renovate's `git-refs` datasource to pin and update a
branch HEAD commit. `apps/skylight-mcp` is the exception: its upstream ref is
not annotated, and `.renovaterc.json5` sets `automerge: false` for that app.
See `apps/skylight-mcp/README.md`.

## Local Builds

```sh
task apps:list
task apps:build APP=skylight-mcp
task apps:smoke APP=skylight-mcp
```

## Releases

Pull requests that change `apps/**` build each changed app for the runner
architecture, load the image locally, and run `smoke.sh`. That workflow does
not log in to GHCR and does not push.

The release workflow publishes on a push to `main` that changes an app (or the
shared workflow, Renovate, or Taskfile inputs), and when Release is started
with `workflow_dispatch`. It builds `linux/amd64` and `linux/arm64` and pushes
provenance and SBOM attestations the same way `jtcressy/containers` does.

Published tags include:

- `rolling`
- the app `VERSION`
- `upstream-<short upstream sha>`
- `sha-<repository commit>`

The index digest is in the release run's Build step, in the bake-action
`Metadata` log group (`image-all` → `containerimage.digest`). Pin that digest
in downstream manifests. Do not pin `rolling`.
