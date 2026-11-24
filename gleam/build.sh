#!/bin/sh
# Build every task in src/ into <outdir>/<task>/.
# Run inside the Gleam dev shell: nix develop .#gleam -c gleam/build.sh <outdir>
set -eu

out=$(realpath -m "${1:?usage: build.sh <outdir>}")
cd "$(dirname "$0")"

rm -rf "$out"
mkdir -p "$out"

for file in src/*.gleam; do
  task=$(basename "$file" .gleam)
  echo "Building gleam task: $task"
  gleam run -m lustre/dev build --minify --outdir="$out/$task" "$task"
  # lustre emits a root-absolute script path; make it relative so the
  # page works under any base path (project page, custom domain, ...)
  sed -i "s|src=\"/$task\.js\"|src=\"$task.js\"|" "$out/$task/index.html"
done
