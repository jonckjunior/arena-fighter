#!/bin/bash

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOVE_CMD="$SCRIPT_DIR/../love.app/Contents/MacOS/love"
HOST="${1:-localhost}"
PORT="${2:-22122}"
INPUT_DELAY="${3:-6}"

case "$PORT" in
    ''|*[!0-9]*)
        echo "Invalid port: $PORT" >&2
        echo "Usage: $0 [host] [port] [input_delay]" >&2
        exit 1
        ;;
esac

case "$INPUT_DELAY" in
    ''|*[!0-9]*)
        echo "Invalid input delay: $INPUT_DELAY" >&2
        echo "Usage: $0 [host] [port] [input_delay]" >&2
        exit 1
        ;;
esac

# Store PIDs
RELAY_PID=
CLIENT1_PID=
CLIENT2_PID=

# Cleanup function
cleanup() {
    echo ""
    echo "Shutting down all processes..."
    kill $RELAY_PID $CLIENT1_PID $CLIENT2_PID 2>/dev/null
    wait 2>/dev/null
    echo "All processes stopped."
    exit 0
}

# Set trap to catch Ctrl+C and SIGTERM
trap cleanup SIGINT SIGTERM

echo "Starting relay server..."
"$LOVE_CMD" "$SCRIPT_DIR/relay" &
RELAY_PID=$!

echo "Waiting 0.5 seconds for relay to start..."
sleep 0.5

echo "Starting client 1..."
"$LOVE_CMD" "$SCRIPT_DIR" --network --host "$HOST" --port "$PORT" --input-delay "$INPUT_DELAY" &
CLIENT1_PID=$!

echo "Waiting 0.5 seconds..."
sleep 0.5

echo "Starting client 2..."
"$LOVE_CMD" "$SCRIPT_DIR" --network --host "$HOST" --port "$PORT" --input-delay "$INPUT_DELAY" &
CLIENT2_PID=$!

echo "All processes started:"
echo "  Relay host: $HOST"
echo "  Relay port: $PORT"
echo "  Input delay: $INPUT_DELAY"
echo "  Relay (PID $RELAY_PID)"
echo "  Client 1 (PID $CLIENT1_PID)"
echo "  Client 2 (PID $CLIENT2_PID)"
echo ""
echo "Press Ctrl+C to stop all processes"

# Wait for all background processes
wait
