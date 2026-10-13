#!/bin/bash
# =============================================================================
# Glaipnir - Generic Host Proxy Wrapper
# =============================================================================
set -euo pipefail

IFS= read -r -d '' RECEIVED_TOKEN || true
EXPECTED_TOKEN="${GLAIPNIR_PROXY_TOKEN:-}"

if [ -z "$EXPECTED_TOKEN" ] || [ "$RECEIVED_TOKEN" != "$EXPECTED_TOKEN" ]; then
    echo "Glaipnir Security Error: Unauthorized proxy access." >&2
    exit 1
fi

IFS= read -r -d '' CTN_WORKSPACE_BASE || true
IFS= read -r -d '' CTN_CWD || true
IFS= read -r -d '' TOOL_NAME || true

cmd=()
while IFS= read -r -d '' arg; do
    cmd+=("$arg")
done

if [ -z "$TOOL_NAME" ]; then
    echo "Glaipnir Proxy Error: Missing tool name." >&2
    exit 1
fi

TOOL_NAME="$(basename "$TOOL_NAME")"

REQUESTED_CMD="$TOOL_NAME"
if [ ${#cmd[@]} -gt 0 ]; then
    REQUESTED_CMD="$TOOL_NAME ${cmd[*]}"
fi

ALLOWLIST_FILE="${GLAIPNIR_PROXY_ALLOWLIST:-}"
IS_ALLOWED=0

if [ -f "$ALLOWLIST_FILE" ]; then
    while IFS= read -r allowed_entry || [ -n "$allowed_entry" ]; do
        [[ "$allowed_entry" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${allowed_entry// }" ]] && continue

        if [[ "$REQUESTED_CMD" == "$allowed_entry" || "$REQUESTED_CMD" == "$allowed_entry "* ]]; then
            IS_ALLOWED=1
            break
        fi
    done < "$ALLOWLIST_FILE"
fi

if [ "$IS_ALLOWED" -ne 1 ]; then
    echo "Glaipnir Security Error: Command '$REQUESTED_CMD' is not whitelisted."
    printf "\n__GLAIPNIR_RC_%s__:1\n" "$RECEIVED_TOKEN"
    exit 1
fi

HOST_WORKSPACE="${GLAIPNIR_HOST_WORKSPACE:-$PWD}"

if [[ "$CTN_CWD" == "$CTN_WORKSPACE_BASE"* ]]; then
    REL_PATH="${CTN_CWD#"$CTN_WORKSPACE_BASE"}"
    REL_PATH="${REL_PATH#/}"
    TARGET_DIR="${HOST_WORKSPACE}/${REL_PATH}"
else
    TARGET_DIR="${HOST_WORKSPACE}"
fi

REAL_TARGET="$(realpath -m "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")"
REAL_BASE="$(realpath "$HOST_WORKSPACE")"

if [[ "$REAL_TARGET" != "$REAL_BASE" && "$REAL_TARGET" != "$REAL_BASE"/* ]]; then
    echo "Glaipnir Security Error: Execution outside of workspace is blocked." >&2
    echo "Requested: $REAL_TARGET | Base: $REAL_BASE" >&2
    exit 1
fi

if [ ! -d "$REAL_TARGET" ]; then
    echo "Glaipnir Error: Directory '$REAL_TARGET' does not exist on host." >&2
    exit 1
fi

cd "$REAL_TARGET"

REAL_BIN="$(command -v "$TOOL_NAME" 2>/dev/null || true)"
if [ -z "$REAL_BIN" ] || [ ! -x "$REAL_BIN" ]; then
    echo "Glaipnir Error: Binary '$TOOL_NAME' not found or not executable on host." >&2
    exit 1
fi

set +e
"$REAL_BIN" "${cmd[@]}"
CMD_RC=$?

printf "\n__GLAIPNIR_RC_%s__:%d\n" "$RECEIVED_TOKEN" "$CMD_RC"
exit "$CMD_RC"
