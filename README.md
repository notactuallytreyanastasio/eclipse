# Illuminates

A Lumines-style puzzle game called **Eclipse**, built as a Phoenix LiveView app with a Game Boy DMG aesthetic. Pure CSS graphics with dot-matrix/dithered rendering. All game logic is pure functions for future PubSub/multi-board extensibility.

## The Game

**Board**: 24 columns x 10 rows. **Pieces**: 2x2 blocks of dark/light tiles (6 patterns). **Clearing**: 2x2 same-color squares get marked, then swept by a left-to-right scanner line.

Arrow keys move and rotate pieces. Space hard-drops. The scanner continuously sweeps across the board, clearing any marked tiles it passes. Gravity drops remaining tiles, which can chain into new matches.

Visit `/play` to play.

## Quick Start

```bash
make up        # build and start containers (app + postgres)
make setup     # create database and run migrations
make logs      # tail container logs
```

The app runs at `http://localhost:4000` by default. Override with `PORT=8080 make up`.

## Architecture

```
lib/illuminates/eclipse/
  piece.ex          # 2x2 block struct, 6 patterns, rotation
  board.ex          # Board grid, collision, gravity, 2x2 matching
  scanner.ex        # Scanner sweep logic
  game_state.ex     # Top-level game state struct
  game.ex           # Pure function game engine

lib/illuminates_web/live/
  eclipse_live.ex   # LiveView with inline HEEx template
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
make up
```

**3. Monitor subagent** — watches container logs and auto-heals errors:

The `/monitor` skill launches a background subagent that continuously tails Docker logs, scans for error patterns (Elixir exceptions, OTP crashes, DB errors, compilation failures), and attempts to fix them automatically. It classifies errors by severity, applies fixes, verifies with `mix compile --warnings-as-errors && mix test`, rebuilds the container, and confirms the fix. If it can't resolve an error after two attempts, it escalates to you.

All observations, actions, and outcomes are logged to the [deciduous](https://github.com/durable-creative/deciduous) decision graph for traceability.

### In practice

Start a Claude Code session and run `/monitor`. This spins up background agents for the server and log watcher. You keep working in the foreground — writing features, running tests, reviewing code. When the server hits an error, the monitor detects it, fixes the source file, rebuilds the container, and logs what it did. You stay uninterrupted.

### Available Make targets

| Target | What it does |
|--------|-------------|
| `make up` | Build and start containers (`PORT=8080 make up` for custom port) |
| `make down` | Stop everything |
| `make logs` | Tail container logs |
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

## Code Quality

```bash
make quality
```

Runs in order: compile (warnings-as-errors), credo (strict), tests, improve-elixir (on changed files only, fed credo output), format. Continues through failures so you see all issues at once.

## Docker

The app runs in Docker Compose with two services:

- **app** — Phoenix server (multi-stage build, Elixir 1.19 / OTP 28)
- **db** — PostgreSQL 17

Database defaults to `illuminates_dev`. Configurable via `DB_USERNAME`, `DB_PASSWORD`, `DB_HOSTNAME`, `DB_DATABASE` environment variables.
