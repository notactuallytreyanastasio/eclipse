# Eclipse

A Lumines-style puzzle game called **Eclipse**, built as a Phoenix LiveView app with a Game Boy DMG aesthetic. Pure CSS graphics with dot-matrix/dithered rendering. All game logic is pure functions for future PubSub/multi-board extensibility.

## The Game

**Board**: 24 columns x 10 rows. **Pieces**: 2x2 blocks of dark/light tiles (6 patterns). **Clearing**: 2x2 same-color squares get marked, then swept by a left-to-right scanner line.

Arrow keys move and rotate pieces. Space hard-drops. The scanner continuously sweeps across the board, clearing any marked tiles it passes. Gravity drops remaining tiles, which can chain into new matches.

Visit `/play` to play.

## Quick Start

```bash
make up        # build and start containers (app + postgres)
make watch     # start file sync for hot reload (run in a separate terminal)
make setup     # create database and run migrations (first time only)
```

The app runs at `http://localhost:4000` by default. Override with `PORT=8080 make up`.

**Hot reload requires `make watch`.** On macOS, Docker volume mounts don't propagate inotify events. `docker compose watch` syncs files into the container with proper filesystem notifications so Phoenix live reload works. Without it, code and CSS changes won't appear until a container rebuild.

## Architecture

```
lib/eclipse/game/
  piece.ex          # 2x2 block struct, 6 patterns, rotation
  board.ex          # Board grid, collision, gravity, 2x2 matching
  scanner.ex        # Scanner sweep logic
  game_state.ex     # Top-level game state struct
  engine.ex         # Pure function game engine

lib/eclipse_web/live/
  game_live.ex      # LiveView with inline HEEx template
```

Game state lives in LiveView assigns. Two independent `Process.send_after` timer loops drive gravity and the scanner. The entire game engine is pure functions operating on plain structs — no GenServers, no side effects. This makes it testable, serializable, and ready to extract into a GenServer with PubSub broadcasting for multiplayer.

## Development with Claude Code

This project is designed for an agent-driven development workflow using Claude Code. The idea is to keep a primary Claude session for interactive work, then delegate the server and monitoring to background subagents.

### The three-agent pattern

**1. Your active session** — where you write code, run tests, and iterate.

**2. Server subagent** — runs the Docker containers in the background:

```
/monitor
```

or manually:

```bash
make up && make watch
```

**3. Monitor subagent** — watches container logs and auto-heals errors:

The `/monitor` skill launches background subagents for the containers, file watcher (hot reload), and a log listener that continuously tails Docker logs, scans for error patterns (Elixir exceptions, OTP crashes, DB errors, compilation failures), and attempts to fix them automatically. Because `docker compose watch` is running, fixes sync into the container automatically — no rebuild needed. If it can't resolve an error after two attempts, it escalates to you.

All observations, actions, and outcomes are logged to the [deciduous](https://github.com/durable-creative/deciduous) decision graph for traceability.

### In practice

Start a Claude Code session and run `/monitor`. This spins up background agents for the server and log watcher. You keep working in the foreground — writing features, running tests, reviewing code. When the server hits an error, the monitor detects it, fixes the source file, rebuilds the container, and logs what it did. You stay uninterrupted.

### Available Make targets

| Target | What it does |
|--------|-------------|
| `make up` | Build and start containers (`PORT=8080 make up` for custom port) |
| `make watch` | Start file sync for hot reload (run after `make up`) |
| `make down` | Stop everything |
| `make logs` | Tail container logs |
| `make graph` | Start the deciduous decision graph viewer |
| `make setup` | Create database and run migrations (first time) |
| `make migrate` | Run pending migrations |
| `make backup` | Dump database to `backups/` |
| `make iex` | IEx shell on the running app |
| `make shell` | Bash shell inside the app container |
| `make compile` | Compile with `--warnings-as-errors` |
| `make test` | Compile + run test suite |
| `make format` | Format the project |
| `make credo` | Run credo in strict mode |
| `make improve` | Run `/improve-elixir` via Claude |
| `make quality` | Full pipeline: compile, credo, test, improve-elixir, format |
| `make heal` | One-shot error diagnosis and fix via Claude |
| `make listen` | Continuous error listener (takes over the session) |
| `make monitor` | Background monitor (subagent, session stays free) |

### Claude skills

| Skill | Purpose |
|-------|---------|
| `/monitor` | Launch background server + log watcher subagents |
| `/listen` | Continuous error listener (foreground) |
| `/heal` | One-shot: diagnose and fix current Docker errors |
| `/improve-elixir` | Systematic code quality improvements |
| `/build-test` | Compile and run tests |
| `/work` | Start a tracked work transaction with deciduous |
| `/quality` | Full quality pipeline |

## Self-Healing Infrastructure

The Makefile, Docker setup, and Claude skills form a closed-loop system where the application monitors itself, fixes its own errors, and records every failure and recovery in a decision graph.

### How it works

The system has three layers:

**1. Hot reload layer** — `docker compose watch` syncs file changes from the host into the running dev container, triggering Phoenix live reload via inotify. When a source file is edited — whether by a human or by the auto-healer — the change propagates into the container within milliseconds. No rebuild cycle, no restart. The app recompiles the changed module and the browser updates.

**2. Error detection layer** — A background agent continuously tails `docker compose logs`, polling every 10 seconds. It pattern-matches against known error signatures:

- Elixir exceptions (`** (RuntimeError)`, `** (FunctionClauseError)`)
- OTP crashes (`CRASH REPORT`, `exited with`)
- Database errors (`(Postgrex.Error)`, `FATAL`)
- Compilation failures (`== Compilation error`)
- HTTP errors (`502`, `503`)

Errors are classified by severity. Critical (app down) and Error (degraded) trigger immediate auto-heal. Warnings are tracked and only escalated after 3 occurrences within 60 seconds.

**3. Auto-heal layer** — When the listener detects a fixable error, it:

1. Reads the stacktrace to locate the source file and line
2. Reads the source to understand the context
3. Edits the file with a fix
4. Verifies locally with `mix compile --warnings-as-errors && mix test`
5. The fix syncs into the container via the watch layer — no manual rebuild
6. Monitors logs for 15 seconds to confirm the error is gone

If the same error persists after two fix attempts, the system stops trying and alerts the developer. It never modifies test files to make tests pass, never weakens error handling to silence errors, and never retries the same fix.

### The decision graph

Every step is logged to [deciduous](https://github.com/durable-creative/deciduous), a decision graph that records the full history of what broke, what was tried, and what worked:

```
observation: "Listener detected: ArgumentError - secret_key_base too short"
    │
    ▼
action: "Auto-heal: replaced SECRET_KEY_BASE with 128-char key"
    │
    ▼
outcome: "Auto-healed: app now returns 200 OK, no errors in logs"
```

Each node carries confidence scores, associated files, and timestamps. Observations link to the actions that addressed them. Actions link to outcomes that verify them. Run `make graph` to view the full graph at `localhost:3000`.

This isn't just logging — it's institutional memory. When a new session starts, `/recover` reads the graph and reconstructs context: what was built, what broke, what decisions were made and why. The graph survives across sessions, across developers, across time.

### The feedback loop

The three layers create a feedback loop:

```
code change ──► watch syncs to container ──► Phoenix recompiles
                                                    │
                                                    ▼
                                              error in logs?
                                              │           │
                                             no           yes
                                              │           │
                                              ▼           ▼
                                          keep watching   auto-heal ──► deciduous logs it
                                                          │
                                                          ▼
                                                   edit source file
                                                          │
                                                          ▼
                                                   watch syncs to container ...
```

The developer works in one terminal. The system heals itself in the background. The graph records everything. When the developer comes back — or a new session starts — the full story is there.

## Code Quality

```bash
make quality
```

Runs in order: compile (warnings-as-errors), credo (strict), tests, improve-elixir (on changed files only, fed credo output), format. Continues through failures so you see all issues at once.

## Docker

The app runs in Docker Compose with three services:

- **app** — Phoenix dev server with live reload (Elixir 1.19 / OTP 28). Uses `Dockerfile.dev` which runs `mix phx.server` in dev mode with esbuild/tailwind watchers. Source code is synced in via `docker compose watch`.
- **db** — PostgreSQL 17 with health checks.
- **graph** — Deciduous decision graph viewer. Built from `Dockerfile.graph` (Rust multi-stage build via `cargo install deciduous`). Mounts `.deciduous/` from the host.

Database defaults to `eclipse_dev`. Configurable via `DB_USERNAME`, `DB_PASSWORD`, `DB_HOSTNAME`, `DB_DATABASE` environment variables.

The original `Dockerfile` (prod release) is still available for production deployments.
