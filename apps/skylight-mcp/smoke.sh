#!/usr/bin/env bash
# Smoke-test the skylight-mcp image with no Skylight credentials and no
# masqueraded route off the host. tools/list must succeed; this script never
# calls a tool and never contacts Skylight.
set -euo pipefail

image="${1:?image is required}"
port=8080
expected_tools=114

fail() {
    echo "smoke: $*" >&2
    if [[ -n "${cid:-}" ]]; then
        docker logs "${cid}" >&2 || true
    fi
    exit 1
}

cid=""
network=""
cleanup() {
    if [[ -n "${cid}" ]]; then
        docker rm -f "${cid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${network}" ]]; then
        docker network rm "${network}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

node_version="$(docker run --rm --entrypoint node "${image}" --version | tr -d '\r')"
[[ "${node_version}" == "v26.13.0" ]] || fail "node version ${node_version}, want v26.13.0"
echo "smoke: node ${node_version}"

proxy_version="$(docker run --rm --entrypoint mcp-proxy "${image}" --version | tr -d '\r')"
[[ "${proxy_version}" == "mcp-proxy 0.13.3" ]] || fail "mcp-proxy version ${proxy_version}, want mcp-proxy 0.13.3"
echo "smoke: ${proxy_version}"

uid="$(docker run --rm --entrypoint id "${image}" -u | tr -d '\r')"
[[ "${uid}" == "10001" ]] || fail "uid ${uid}, want 10001"
echo "smoke: uid ${uid}"

wget_banner="$(docker run --rm --entrypoint wget "${image}" --help 2>&1 | head -n 1 || true)"
[[ "${wget_banner}" == BusyBox* ]] || fail "wget is not BusyBox: ${wget_banner}"
echo "smoke: ${wget_banner}"

docker run --rm --entrypoint /bin/sh "${image}" -c \
    'test -f /opt/skylight-mcp/dist/index.js && grep -q "\"version\": \"18.0.8\"" /opt/skylight-mcp/node_modules/dotenv/package.json'
echo "smoke: dist/index.js and dotenv 18.0.8 are present"

network="skylight-mcp-smoke-$$"
# Port publishing still works. Masquerade is off, so the container cannot open
# a connection off the host and cannot reach Skylight. An internal network
# also drops the published port this check curls.
docker network create \
    --opt com.docker.network.bridge.enable_ip_masquerade=false \
    "${network}" >/dev/null

cid="$(docker run -d \
    --network "${network}" \
    -p "127.0.0.1:${port}:${port}" \
    "${image}" \
    --host 0.0.0.0 --port "${port}" -- node /opt/skylight-mcp/dist/index.js)"

if docker inspect "${cid}" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q '^SKYLIGHT_'; then
    fail "container env contains SKYLIGHT_ variables"
fi

code=""
for _ in $(seq 1 30); do
    if ! docker inspect -f '{{.State.Running}}' "${cid}" | grep -qx true; then
        fail "container exited before /healthz returned 204"
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' "127.0.0.1:${port}/healthz" || true)"
    if [[ "${code}" == "204" ]]; then
        break
    fi
    sleep 1
done
[[ "${code}" == "204" ]] || fail "/healthz returned ${code:-none}, want 204"
echo "smoke: /healthz ${code}"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"; cleanup' EXIT

session_id=""
mcp_post() {
    local payload="$1"
    local body="$2"
    local hdr="$3"
    local curl_args=(
        -sS
        -D "${hdr}"
        -o "${body}"
        -w '%{http_code}'
        --max-time 30
        -H 'Content-Type: application/json'
        -H 'Accept: application/json, text/event-stream'
    )
    if [[ -n "${session_id}" ]]; then
        curl_args+=(-H "Mcp-Session-Id: ${session_id}")
    fi
    curl "${curl_args[@]}" -d "${payload}" "http://127.0.0.1:${port}/mcp"
}

parse_jsonrpc() {
    python3 - "$1" <<'PY'
import json
import sys

raw = open(sys.argv[1], encoding="utf-8").read().strip()
if not raw:
    print("")
    print("")
    raise SystemExit(0)
if raw.startswith("event:") or "\ndata:" in "\n" + raw:
    data = [line[5:].strip() for line in raw.splitlines() if line.startswith("data:")]
    if not data:
        raise SystemExit("SSE body had no data line")
    raw = data[-1]
message = json.loads(raw)
if "error" in message:
    raise SystemExit(json.dumps(message["error"]))
result = message.get("result", {})
tools = result.get("tools")
if isinstance(tools, list):
    print(str(len(tools)))
    cursor = result.get("nextCursor") or ""
    print(cursor)
else:
    print("")
    print("")
PY
}

init_body="${workdir}/init.json"
init_hdr="${workdir}/init.hdr"
init_code="$(mcp_post '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"skylight-mcp-smoke","version":"0"}}}' "${init_body}" "${init_hdr}")"
[[ "${init_code}" == "200" ]] || fail "initialize HTTP ${init_code}: $(cat "${init_body}")"
session_id="$(awk 'tolower($1)=="mcp-session-id:" {print $2}' "${init_hdr}" | tr -d '\r')"
[[ -n "${session_id}" ]] || fail "initialize did not return mcp-session-id: $(cat "${init_hdr}")"
parse_jsonrpc "${init_body}" >/dev/null || fail "initialize rejected: $(cat "${init_body}")"

note_body="${workdir}/note.json"
note_hdr="${workdir}/note.hdr"
note_code="$(mcp_post '{"jsonrpc":"2.0","method":"notifications/initialized"}' "${note_body}" "${note_hdr}")"
[[ "${note_code}" == "200" || "${note_code}" == "202" ]] || fail "initialized HTTP ${note_code}: $(cat "${note_body}")"

cursor=""
total=0
page=0
while true; do
    page=$((page + 1))
    if [[ "${page}" -gt 20 ]]; then
        fail "tools/list did not finish after ${total} tools"
    fi
    if [[ -z "${cursor}" ]]; then
        payload='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    else
        payload="$(python3 -c 'import json,sys; print(json.dumps({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"cursor":sys.argv[1]}}))' "${cursor}")"
    fi
    body="${workdir}/tools-${page}.json"
    hdr="${workdir}/tools-${page}.hdr"
    tools_code="$(mcp_post "${payload}" "${body}" "${hdr}")"
    [[ "${tools_code}" == "200" ]] || fail "tools/list HTTP ${tools_code}: $(cat "${body}")"
    parsed="$(parse_jsonrpc "${body}")" || fail "tools/list rejected: $(cat "${body}")"
    count="$(printf '%s\n' "${parsed}" | sed -n '1p')"
    cursor="$(printf '%s\n' "${parsed}" | sed -n '2p')"
    [[ "${count}" =~ ^[0-9]+$ ]] || fail "tools/list had no tools array: $(cat "${body}")"
    total=$((total + count))
    [[ -n "${cursor}" ]] || break
done

[[ "${total}" == "${expected_tools}" ]] || fail "tools/list returned ${total} tools, want ${expected_tools}"
echo "smoke: tools/list ${total} with no credentials"

if ! docker inspect -f '{{.State.Running}}' "${cid}" | grep -qx true; then
    fail "container exited after tools/list"
fi

echo "smoke: ok ${image}"
