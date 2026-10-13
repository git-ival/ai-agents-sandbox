#!/bin/sh
# =============================================================================
# Glaipnir - Container Proxy Client Shim
# =============================================================================
set -e

PORT="${GLAIPNIR_PROXY_PORT:-}"
TOKEN="${GLAIPNIR_PROXY_TOKEN:-}"
HOST="${GLAIPNIR_PROXY_HOST:-127.0.0.1}"

if [ -z "$PORT" ] || [ -z "$TOKEN" ]; then
    echo "Glaipnir Error: Proxy configuration missing (PORT or TOKEN not set)."\
        >&2
    exit 1
fi

if ! command -v socat >/dev/null 2>&1; then
    echo "Glaipnir Error: 'socat' is missing in container." >&2
    exit 1
fi

TOOL_NAME="$(basename "$0")"
WORKSPACE_DIR="${AI_WORKSPACE:-/home/aiuser/workspace}"
MARKER="__GLAIPNIR_RC_${TOKEN}__:"

{
    printf "%s\0" "$TOKEN"
    printf "%s\0" "$WORKSPACE_DIR"
    printf "%s\0" "$PWD"
    printf "%s\0" "$TOOL_NAME"
    for arg in "$@"; do
        printf "%s\0" "$arg"
    done
} | socat - "TCP:$HOST:$PORT" | {
    RC=1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "${MARKER}"*)
                RC="${line#"${MARKER}"}"
                ;;
            *)
                printf "%s\n" "$line"
                ;;
        esac
    done
    exit "$RC"
}
