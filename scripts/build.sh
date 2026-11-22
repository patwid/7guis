#!/bin/sh
# Build every task in src/ into public/<task>/ and generate public/index.html.
# Run inside the dev shell: nix develop -c ./scripts/build.sh
set -eu

cd "$(dirname "$0")/.."

out=public
rm -rf "$out"
mkdir -p "$out"

links=""
for file in src/*.gleam; do
  task=$(basename "$file" .gleam)
  echo "Building task: $task"
  gleam run -m lustre/dev build --minify --outdir="$out/$task" "$task"
  # lustre emits a root-absolute script path; make it relative so the
  # page works under any base path (project page, custom domain, ...)
  sed -i "s|src=\"/$task\.js\"|src=\"$task.js\"|" "$out/$task/index.html"
  title=$(echo "$task" | sed -E 's/_/ /g; s/\b(.)/\u\1/g')
  links="$links    <li><a href=\"$task\">$title</a></li>
"
done

cat >"$out/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>7GUIs</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 1rem; }
    li { margin: 0.25rem 0; }
  </style>
</head>
<body>
  <ul>
$links  </ul>
</body>
</html>
HTML
