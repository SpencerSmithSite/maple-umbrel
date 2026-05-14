#!/bin/sh
# Read API key from shared volume if present, then start proxy.
# Poll every 10s and restart if the key file changes.
KEY_FILE=/config/api-key

get_checksum() { md5sum "$KEY_FILE" 2>/dev/null || echo "none"; }

start_proxy() {
  if [ -f "$KEY_FILE" ] && [ -s "$KEY_FILE" ]; then
    export MAPLE_API_KEY=$(cat "$KEY_FILE" | tr -d '[:space:]')
  else
    unset MAPLE_API_KEY
  fi
  /usr/local/bin/maple-proxy &
  PROXY_PID=$!
  echo "maple-proxy started (pid $PROXY_PID), MAPLE_API_KEY=$([ -n "$MAPLE_API_KEY" ] && echo set || echo unset)"
}

CHECKSUM=$(get_checksum)
start_proxy

while true; do
  sleep 10
  NEW_CHECKSUM=$(get_checksum)
  if [ "$NEW_CHECKSUM" != "$CHECKSUM" ]; then
    echo "Key file changed, restarting maple-proxy..."
    CHECKSUM="$NEW_CHECKSUM"
    kill "$PROXY_PID" 2>/dev/null
    wait "$PROXY_PID" 2>/dev/null
    start_proxy
  fi
done
