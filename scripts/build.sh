#!/bin/sh
# Build every implementation into public/<impl>/<task>/ (each in its own dev
# shell) and generate public/index.html linking all of them.
# Usage: ./scripts/build.sh
set -eu

cd "$(dirname "$0")/.."

out=public
impls="gleam elm"

rm -rf "$out"
mkdir -p "$out"

for impl in $impls; do
  nix develop ".#$impl" -c "./$impl/build.sh" "$out/$impl"
done

# The Gleam tasks used to live at the site root; keep those links working.
for dir in "$out"/gleam/*/; do
  task=$(basename "$dir")
  mkdir -p "$out/$task"
  cat >"$out/$task/index.html" <<HTML
<!doctype html>
<meta charset="utf-8" />
<meta http-equiv="refresh" content="0; url=../gleam/$task/" />
<link rel="canonical" href="../gleam/$task/" />
<a href="../gleam/$task/">Moved to gleam/$task</a>
HTML
done

tasks=$(for impl in $impls; do ls "$out/$impl"; done | sort -u)

header=""
for impl in $impls; do
  header="$header<th>$impl</th>"
done

rows=""
for task in $tasks; do
  title=$(echo "$task" | sed -E 's/_/ /g; s/\b(.)/\u\1/g')
  cells=""
  for impl in $impls; do
    if [ -d "$out/$impl/$task" ]; then
      cells="$cells<td><a href=\"$impl/$task/\">$impl</a></td>"
    else
      cells="$cells<td>&ndash;</td>"
    fi
  done
  rows="$rows    <tr><th>$title</th>$cells</tr>
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
    table { border-collapse: collapse; }
    th, td { padding: 0.25rem 1rem 0.25rem 0; text-align: left; }
  </style>
</head>
<body>
  <table>
    <tr><th></th>$header</tr>
$rows  </table>
</body>
</html>
HTML
