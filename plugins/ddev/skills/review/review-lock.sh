#!/usr/bin/env bash
# Serialize Docker work between agent sessions on this machine, such as
# reviews and /ddev:ci-failure.
#   review-lock.sh acquire <label>  wait for the lock, then hold it until
#                                   release, or for REVIEW_LOCK_MAX seconds
#                                   (3h) if the session is lost
#   review-lock.sh release <label>  drop the lock held under <label>
#
# The lock is a directory of numbered files. The highest number holds the
# current "<holder> <since>", where holder - means free. Every change adds
# the next number with ln, which fails if the file exists, on Linux, macOS
# and Git Bash. So when sessions see the same free or expired lock, only one
# gets it, and the current number is never removed.
set -euo pipefail

dir=${REVIEW_LOCK:-$HOME/tmp/.ddev-docker-lock}
max=${REVIEW_LOCK_MAX:-10800}
mkdir -p "$dir"

numbers() {
  local f
  for f in "$dir"/*; do
    f=${f##*/}
    case $f in '' | *[!0-9]*) ;; *) echo "$f" ;; esac
  done
}
latest() { numbers | sort -n | tail -n 1; }

# Sets n, holder and since from the highest number. Fails if a newer one
# removed it before the read, so the caller reads again.
current() {
  n=$(latest)
  n=${n:-0}
  holder=-
  since=0
  [ "$n" -ne 0 ] || return 0
  if read -r holder since 2>/dev/null <"$dir/$n" && [ -n "$holder" ]; then
    case $since in '' | *[!0-9]*) ;; *) return 0 ;; esac
  fi
  [ -e "$dir/$n" ] || return 1
  echo "can't read the lock state in $dir/$n; remove that file" >&2
  exit 1
}

describe() {
  echo "$holder for $((($(date +%s) - since) / 60))m"
}

# Writes "$1 <now>" as number next=n+1, if no other session wrote it first,
# and removes the numbers below it.
advance() {
  local tmp=$dir/.tmp.$$ f
  next=$((n + 1))
  echo "$1 $(date +%s)" >"$tmp"
  if ! ln "$tmp" "$dir/$next" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  for f in $(numbers); do
    if [ "$f" -lt "$next" ]; then rm -f "$dir/$f"; fi
  done
}

case ${1:-} in
acquire)
  label=${2:?usage: review-lock.sh acquire <label>}
  case $label in - | *[[:space:]]*) echo "label must be one word, not -" >&2; exit 2 ;; esac
  waiting=''
  while :; do
    current || continue
    if [ "$holder" = "$label" ]; then
      echo "already held: $(describe)"
      exit 0
    fi
    if [ "$holder" = - ] || [ $(($(date +%s) - since)) -gt "$max" ]; then
      expired=$holder
      advance "$label" || continue
      # A session that read an old state can recreate a number that was
      # removed after it was replaced. A higher number exists then.
      [ "$(latest)" = "$next" ] || continue
      [ "$expired" = - ] || echo "expired: $expired"
      echo "acquired: $label"
      exit 0
    fi
    if [ -z "$waiting" ]; then
      echo "waiting for: $(describe)"
      waiting=1
    fi
    sleep 5
  done
  ;;
release)
  label=${2:?usage: review-lock.sh release <label>}
  until current; do :; done
  if [ "$holder" = - ]; then
    echo "not held"
  elif [ "$holder" != "$label" ]; then
    echo "not held by $label: $(describe)"
    exit 1
  elif advance -; then
    echo "released: $label"
  else
    echo "not held by $label: another session took it after it expired"
    exit 1
  fi
  ;;
*)
  echo "usage: review-lock.sh acquire|release <label>" >&2
  exit 2
  ;;
esac
