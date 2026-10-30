#!/usr/bin/env bash
# List, or power off, DDEV on every local Docker context except the one a
# review is about to use: local engines compete for the same ports.
# Usage: poweroff-others.sh [--poweroff] <context>
# Without --poweroff it only lists them. Run it with the user's own ddev on
# PATH, not a review build.
set -euo pipefail

poweroff=
if [ "${1:-}" = --poweroff ]; then poweroff=1; shift; fi
keep=${1:?usage: poweroff-others.sh [--poweroff] <context>}
# DOCKER_HOST overrides DOCKER_CONTEXT, and the review's config isn't the user's.
unset DOCKER_HOST DDEV_XDG_CONFIG_HOME

# A 10s limit for engines that hang. perl's alarm survives exec, and perl
# ships with macOS and Git Bash, which have no timeout command.
quick() { perl -e 'alarm shift; exec @ARGV' 10 "$@"; }
engine_id() { DOCKER_CONTEXT=$1 quick docker info --format '{{.ID}}' 2>/dev/null || true; }

# Contexts can point at the same engine, such as default and desktop-linux.
keep_id=$(engine_id "$keep")

docker context ls --format '{{.Name}} {{.DockerEndpoint}}' |
  while read -r name endpoint; do
    case $endpoint in unix:* | npipe:*) ;; *) continue ;; esac
    [ "$name" != "$keep" ] || continue
    [ -z "$keep_id" ] || [ "$(engine_id "$name")" != "$keep_id" ] || continue
    [ -n "$(DOCKER_CONTEXT=$name quick docker ps -q --filter label=com.ddev.platform=ddev 2>/dev/null)" ] || continue
    if [ -z "$poweroff" ]; then echo "ddev is running on $name"; continue; fi
    echo "powering off ddev on $name"
    DOCKER_CONTEXT=$name ddev poweroff </dev/null
  done
