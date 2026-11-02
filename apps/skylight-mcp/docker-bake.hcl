target "docker-metadata-action" {}

variable "APP" {
  default = "skylight-mcp"
}

variable "VERSION" {
  default = "1.4.7"
}

variable "UPSTREAM_REF" {
  // Pinned by hand to the reviewed v1.4.7 commit. Do not add a Renovate
  // datasource annotation: the repo-wide docker-bake.hcl rule automerges
  // source bumps, and that would publish unreviewed upstream code to rolling.
  default = "5f22579d18a09cc4120401aca1f5f4deb5fe3915"
}

variable "SOURCE" {
  default = "https://github.com/chrischall/skylight-mcp"
}

variable "NODE_IMAGE" {
  default = "node:26.13.0-alpine@sha256:c6ad9e9c1d80f6eb607c26b4b0a132ff7a2344fad1c78ea3baa2a7d4c8de6d94"
}

variable "PROXY_IMAGE" {
  default = "ghcr.io/sparfenyuk/mcp-proxy:v0.13.3@sha256:93fd47638ea9b5b017cf826f2c7ea4f3ce9d15e7984970de25a9b0aebef66189"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  context = "."
  dockerfile = "Dockerfile"
  args = {
    NODE_IMAGE   = "${NODE_IMAGE}"
    PROXY_IMAGE  = "${PROXY_IMAGE}"
    SOURCE       = "${SOURCE}"
    UPSTREAM_REF = "${UPSTREAM_REF}"
  }
  labels = {
    "org.opencontainers.image.description" = "Skylight Calendar MCP server (stdio) behind mcp-proxy Streamable HTTP"
    "org.opencontainers.image.source"      = "https://github.com/jtcressy-home/containers"
    "org.opencontainers.image.upstream"    = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:local"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]
}
