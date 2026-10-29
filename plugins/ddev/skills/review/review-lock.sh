#!/usr/bin/env bash
# Serialize Docker work between review sessions on this machine.
#   review-lock.sh acquire <label>  wait for the lock, then hold it until
#                                   release, or for REVIEW_LOCK_MAX seconds
#                                   (3h) if the session is lost
#   review-lock.sh release <label>  drop the lock held under <label>
#   review-lock.sh status           show who holds it
# The lock is a directory: mkdir is atomic on Linux, macOS and Git Bash.
set -euo pipefail

lock=${REVIEW_LOCK:-$HOME/tmp/.ddev-review.lock}
owner=$lock/owner
max=${REVIEW_LOCK_MAX:-10800}
mkdir -p "$(dirname "$lock")"

describe() {
  local label since
  read -r label since 2>/dev/null <"$owner" || { echo "unknown holder"; return; }
  echo "$label for $((($(date +%s) - since) / 60))m"
}

# Remove a lock older than $max, or one whose holder never wrote its owner
# file (checked after a minute, so a holder that just took it isn't hit).
expire() {
  local label='' since
  if read -r label since 2>/dev/null <"$owner"; then
    (($(date +%s) - since > max)) || return 0
  elif [ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    return 0
  fi
  rm -rf "$lock"
  echo "expired: ${label:-unknown holder}"
}

case ${1:-} in
acquire)
  label=${2:?usage: review-lock.sh acquire <label>}
  if read -r held _ 2>/dev/null <"$owner" && [ "$held" = "$label" ]; then
    echo "already held: $(describe)"
    exit 0
  fi
  waiting=
  until mkdir "$lock" 2>/dev/null; do
    expire
    if [ -z "$waiting" ] && [ -d "$lock" ]; then
      echo "waiting for: $(describe)"
      waiting=1
    fi
    sleep 5
  done
  echo "$label $(date +%s)" >"$owner"
  echo "acquired: $label"
  ;;
release)
  label=${2:?usage: review-lock.sh release <label>}
  read -r held _ 2>/dev/null <"$owner" || { echo "not held"; exit 0; }
  if [ "$held" != "$label" ]; then
    echo "not held by $label: $(describe)"
    exit 1
  fi
  rm -rf "$lock"
  echo "released: $label"
  ;;
status)
  expire
  if [ -d "$lock" ]; then
    echo "held: $(describe)"
  else
    echo "free"
  fi
  ;;
*)
  echo "usage: review-lock.sh acquire|release <label> | status" >&2
  exit 2
  ;;
esac
