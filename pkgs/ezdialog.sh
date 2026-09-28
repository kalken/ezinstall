#!/usr/bin/env bash
if [ $# -lt 1 ]; then
  echo "Usage: ezdialog MESSAGE" >&2
  exit 2
fi
echo "$1"
read -rp "Continue? [Y/n]: " REPLY
case "$REPLY" in
  [nN]*) exit 1 ;;
  *) exit 0 ;;
esac
