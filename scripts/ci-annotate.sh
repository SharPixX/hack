#!/usr/bin/env bash
# Publishes the tail of a log file as GitHub Actions error annotations, so the
# reason of a failed CI step is visible on the run page without opening raw logs.
#   scripts/ci-annotate.sh <file> <title> [lines]
set -uo pipefail

file=$1
title=$2
lines=${3:-120}
[[ -f "$file" ]] || exit 0

# strip ANSI colours, keep the last N lines, split into chunks (max 10 annotations per step)
sed 's/\x1b\[[0-9;]*m//g' "$file" | tail -n "$lines" | split -l 30 - /tmp/ci-annotate-chunk.
part=0
for chunk in /tmp/ci-annotate-chunk.*; do
  part=$((part + 1))
  msg=$(sed -e 's/%/%25/g' "$chunk" | sed -e ':a;N;$!ba;s/\r//g;s/\n/%0A/g')
  echo "::error title=${title} (${part})::${msg}"
done
rm -f /tmp/ci-annotate-chunk.*
