# 7GUIs

[Gleam](https://gleam.run)/[Lustre](https://lustre.build) implementation of the [7GUIs](https://eugenkiss.github.io/7guis/) benchmark tasks, deployed to GitHub Pages: https://patwid.github.io/7guis/

Each task is an independent Lustre application in `src/`:

- `counter`
- `temperature_converter`
- `flight_booker`
- `timer`
- `crud`
- `circle_drawer`
- `cells`

## Development Environment

Requires Nix with flakes. Enter the dev shell with `nix develop` (or `direnv allow` for automatic loading). Provides: gleam, bun, nodejs, erlang, rebar3.

## Commands

```bash
# Dev server with hot reload for a specific task
gleam run -m lustre/dev start <task>       # e.g. gleam run -m lustre/dev start counter

# Production build for a specific task
gleam run -m lustre/dev build --minify --outdir="public/<task>" <task>

# Build all tasks into public/ (plus an index page)
./scripts/build.sh

# Run tests
gleam test

# Format code
gleam format

# Type check
gleam check
```

## Architecture

Each task follows Lustre's Elm Architecture (Model-View-Update):

- **Model**: immutable state type
- **Msg**: union type of all possible messages
- **init()**: returns initial model (or `#(Model, Effect(Msg))` for tasks with effects)
- **update(model, msg)**: pure state transition function
- **view(model)**: renders model to `Element(Msg)`

Entry point is `lustre.application()` or `lustre.simple()` depending on whether effects are needed.

**FFI**: Browser APIs not available in Gleam are accessed via `@external` declarations pointing to `.ffi.mjs` files (e.g., `timer.ffi.mjs` for `setInterval`, `circle_drawer.ffi.mjs` for dialog APIs).

## CI/CD

GitHub Actions runs `scripts/build.sh` inside the Nix dev shell on every push and pull request. It builds every `src/*.gleam` task into `public/<task>/` and rewrites script paths to be relative so the pages work under the GitHub Pages subdirectory. Pushes to master then deploy `public/` to GitHub Pages.
