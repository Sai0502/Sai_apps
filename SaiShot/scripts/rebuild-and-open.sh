#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="SaiShot"
APP_BUNDLE="$APP_NAME.app"

echo "==> [1/3] Killing running $APP_NAME..."
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    pkill -x "$APP_NAME"
    # Wait for process to exit (up to 5 seconds)
    for i in $(seq 1 50); do
        if ! pgrep -x "$APP_NAME" > /dev/null 2>&1; then
            echo "==> $APP_NAME terminated."
            break
        fi
        sleep 0.1
    done
    # Force kill if still running
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "==> Force killing $APP_NAME..."
        pkill -9 -x "$APP_NAME"
        sleep 0.5
    fi
else
    echo "==> $APP_NAME is not running, skipping kill."
fi

# This project intentionally runs the bundle from the project root instead of
# installing a second copy. Two bundles with the same id would compete for
# hotkeys and TCC.
echo "==> [2/3] Building $APP_NAME..."
bash scripts/bundle.sh
echo "==> Build succeeded."

echo "==> [3/3] Launching $APP_BUNDLE and waiting for $APP_NAME to start..."
open "$APP_BUNDLE"
for i in $(seq 1 50); do
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "==> ✅ $APP_NAME is running (PID: $(pgrep -x "$APP_NAME"))."
        exit 0
    fi
    sleep 0.1
done

echo "==> ⚠️ $APP_NAME did not start within 5 seconds."
exit 1
