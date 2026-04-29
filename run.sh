#!/bin/bash

SCRIPT=$1

if [ -z "$SCRIPT" ]; then
  echo "Usage: ./run.sh <script.bt>"
  exit 1
fi

if [ "$EUID" -eq 0 ]; then
  exec bpftrace "$SCRIPT"
fi

if sudo -n true 2>/dev/null; then
  exec sudo bpftrace "$SCRIPT"
fi

echo "Cannot run bpftrace as non-root because sudo is unavailable or misconfigured."
echo "Try running this from a root shell, or fix sudo inside the guest first."
exit 1
