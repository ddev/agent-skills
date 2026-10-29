#!/usr/bin/env bash
# Checks a commit message, or with --body a PR or issue body, for the
# problems reviewers flag most. Prints file:line: problem for each, and exits
# 1 if it found any.
#
# Usage: check-message.sh [--body] <file>

set -eu

mode=commit
if [ "${1:-}" = "--body" ]; then
  mode=body
  shift
fi
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: $0 [--body] <file>" >&2
  exit 2
fi

awk -v mode="$mode" -v file="$1" '
function report(line, msg) { printf "%s:%d: %s\n", file, line, msg; bad = 1 }
function is_heading(s) { return s ~ /^#+ / }
# A line that GitHub starts a new block with, rather than joining it to the
# paragraph above with <br>.
function starts_block(s) {
  return s ~ /^ *([-*+] |[0-9]+[.)] |#|\||>|```|~~~)/
}
function is_trailer(s) { return s ~ /^[A-Za-z][A-Za-z-]*: / }
function check_words(s,    w) {
  s = tolower(s)
  while (match(s, "(^|[^a-z])(" words ")([^a-z-]|$)")) {
    w = substr(s, RSTART, RLENGTH)
    gsub(/^[^a-z]|[^a-z]$/, "", w)
    report(NR, "avoid \"" w "\"")
    s = substr(s, RSTART + RLENGTH)
  }
}

BEGIN {
  types = "^(build|chore|ci|docs|feat|fix|perf|refactor|style|test)(\\([^)]+\\))?!?: "
  words = "comprehensive|seamless(ly)?|genuine(ly)?|honest(ly)?|truly|really|perfect(ly)?|robust|powerful|effortless(ly)?|production-ready|tremendous(ly)?|dramatically|revolutionary|delve|elevate|unleash"
}

{ sub(/\r$/, "") }

mode == "commit" && NR == 1 {
  if ($0 !~ types)
    report(NR, "title is not <type>[(scope)][!]: <description>")
  desc = $0
  sub(/^[^:]*: /, "", desc)
  if (desc ~ /^[A-Z][a-z]/)
    report(NR, "title description starts with a capital letter")
  if ($0 ~ /\.$/)
    report(NR, "title ends with a period")
  short = $0
  gsub(/, (fixes|for) [A-Za-z0-9_.\/-]*#[0-9]+/, "", short)
  sub(/ \[skip ci\]$/, "", short)
  sub(/ \(#[0-9]+\)$/, "", short)
  if (length(short) > 72)
    report(NR, "title is " length(short) " characters without issue links; aim for about 60, at most 72")
  check_words($0)
  next
}
mode == "commit" && NR == 2 {
  if ($0 != "")
    report(NR, "line 2 must be empty")
  next
}

/^ *(```|~~~)/ { fence = !fence; content = 1; prev = ""; next }
fence { next }

{
  if ($0 != "" && prev != "" && !starts_block($0) && !is_heading(prev) \
      && !(is_trailer($0) && is_trailer(prev)))
    report(NR, "line break inside a paragraph; GitHub shows it as <br>")

  if (is_heading($0)) {
    if (heading && !content)
      report(heading, "empty section: drop it, heading included")
    heading = NR
    content = 0
  } else if ($0 != "") {
    content = 1
  }

  # Inline code can name a placeholder or a word without using it.
  text = $0
  gsub(/`[^`]*`/, "", text)
  if (text ~ /REPLACE_ME/)
    report(NR, "placeholder left in")
  if (text ~ /<!--/)
    report(NR, "template comment left in")

  check_words(text)
  prev = $0
}

END {
  if (heading && !content)
    report(heading, "empty section: drop it, heading included")
  exit bad
}
' "$1"
