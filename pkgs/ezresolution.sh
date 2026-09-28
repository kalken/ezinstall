#!/usr/bin/env bash
if [ $# -ne 1 ]; then
  echo "Usage: ezresolution WIDTHxHEIGHT" >&2
  exit 1
fi
OUTPUT=$(xrandr --query | awk '/ connected/{print $1; exit}')
if [ -z "$OUTPUT" ]; then
  echo "No connected display output found." >&2
  exit 1
fi
xrandr --output "$OUTPUT" --mode "$1"
