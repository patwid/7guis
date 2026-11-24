# 7GUIs

Implementations of the [7GUIs](https://eugenkiss.github.io/7guis/) benchmark tasks, deployed to GitHub Pages: https://patwid.github.io/7guis/

- `gleam/`: [Gleam](https://gleam.run)/[Lustre](https://lustre.build), one Lustre application per task in `gleam/src/`
- `elm/`: [Elm](https://elm-lang.org), one `Browser` program per task module in `elm/src/` (the cells task's helper modules live in `elm/src/Cells/`)

Tasks: counter, temperature converter, flight booker, timer, CRUD, circle drawer, cells.

## Development Environment

Requires Nix with flakes. Each implementation has its own dev shell:

- `nix develop .#gleam`: gleam, bun, nodejs, erlang, rebar3
- `nix develop .#elm`: elm, elm-format, elm-test, esbuild
- `nix develop` (or `direnv allow`): both combined

## Commands

```bash
# Build all implementations into public/<impl>/<task>/ (plus an index page);
# enters each dev shell itself
./scripts/build.sh

# Gleam (run in gleam/)
gleam run -m lustre/dev start <task>       # dev server, e.g. counter
gleam test
gleam format
gleam check

# Elm (run in elm/)
elm reactor                                # dev server, open src/<Task>.elm (not flight
                                           # booker, which needs flags, nor circle drawer,
                                           # which needs ports; see build.sh)
elm make src/<Task>.elm --output=/dev/null # type check
elm-test                                   # tests in tests/
elm-format --yes src tests
```

## Architecture

Each task follows the Elm Architecture, in Gleam via Lustre (Model-View-Update):

- **Model**: immutable state type
- **Msg**: union type of all possible messages
- **init()**: returns initial model (or `#(Model, Effect(Msg))` for tasks with effects)
- **update(model, msg)**: pure state transition function
- **view(model)**: renders model to `Element(Msg)`

Entry point is `lustre.application()` or `lustre.simple()` depending on whether effects are needed.

**FFI (Gleam)**: Browser APIs not available in Gleam are accessed via `@external` declarations pointing to `.ffi.mjs` files (e.g., `timer.ffi.mjs` for `setInterval`, `circle_drawer.ffi.mjs` for dialog APIs).

**Elm**: the same structure, with `Browser.sandbox` / `Browser.element` as entry points and ports in place of FFI: a task's `src/<Task>.ports.js` (e.g. `CircleDrawer.ports.js` for the dialog API) defines `connectPorts(app)`, which `elm/build.sh` bundles and calls.

## CI/CD

GitHub Actions runs `scripts/build.sh` on every push and pull request. It runs `gleam/build.sh` and `elm/build.sh`, each in its own dev shell, to build every task into `public/<impl>/<task>/` with relative script paths, so the pages work under the GitHub Pages subdirectory. It then writes `public/index.html` (a task × implementation table) and redirect pages at the old `public/<task>/` URLs. Pushes to master then deploy `public/` to GitHub Pages.
