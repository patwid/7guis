#!/bin/sh
# Build every task module in src/ into <outdir>/<task>/, where <task> is the
# module name in snake_case (Counter -> counter, FlightBooker -> flight_booker).
# Run inside the Elm dev shell: nix develop .#elm -c elm/build.sh <outdir>
set -eu

out=$(realpath -m "${1:?usage: build.sh <outdir>}")
cd "$(dirname "$0")"

rm -rf "$out"
mkdir -p "$out"

for file in src/*.elm; do
  module=$(basename "$file" .elm)
  task=$(echo "$module" | sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  echo "Building elm task: $task"
  mkdir -p "$out/$task"
  elm make --optimize --output="$out/$task/elm.js" "$file"
  esbuild --minify --log-level=warning --allow-overwrite --outfile="$out/$task/$task.js" "$out/$task/elm.js"
  rm "$out/$task/elm.js"
  cat >"$out/$task/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$module</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; }
    #app { padding: 1rem; }
    .row { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; }
    .column { display: flex; flex-direction: column; align-items: flex-start; gap: 0.5rem; }
    label { display: flex; align-items: center; gap: 0.5rem; }
    input, select, button { font: inherit; }
    input[type="range"] { margin: 0; }
  </style>
  <script src="$task.js"></script>
</head>
<body>
  <div id="app"><div id="elm"></div></div>
  <script>Elm.$module.init({ node: document.getElementById("elm") });</script>
</body>
</html>
HTML
done
