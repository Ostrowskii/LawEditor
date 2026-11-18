#!/bin/sh
# Runs LawEditor's server in the home of the projects: ~/LawEditor, or LAWEDITOR_HOME.
# The server is told where LawEditor itself is (its page in dist/, what the AIs are told in harness/).
root=$(cd "$(dirname "$0")" && pwd)
home=${LAWEDITOR_HOME:-$HOME/LawEditor}
# 0.1.10 kept the projects inside LawEditor's own folder. The first time, they are copied to the home
# (never moved: the originals stay where they were).
if [ ! -d "$home" ] && [ -d "$root/projects" ]; then
  mkdir -p "$home"
  for d in "$root"/projects/*/; do d=${d%/}; [ -d "$d" ] && cp -R "$d" "$home/"; done   # no "/" at the end: with one, cp copies what is inside
  echo "Your projects were copied from $root/projects to $home. The originals are still there."
fi
mkdir -p "$home" && cd "$home" && exec "$root/dist/laweditor-server" "$root"
