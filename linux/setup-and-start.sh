#!/usr/bin/env bash
set -Eeuo pipefail

# Compatibility shim for an installer already running from an older checkout.
# This script intentionally no longer starts CS2; launch is Instance-only.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
echo "DEPRECATED: setup-and-start.sh no longer starts CS2."
echo "Delegating to the no-launch setup worker. For normal operations use linux/install.sh."
exec bash "$ROOT_DIR/linux/setup.sh" "$@"
