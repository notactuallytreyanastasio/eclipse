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

## Development Flow

This project uses an agent-driven workflow with [Claude Code](https://claude.ai/claude-code). A primary session handles interactive work while background subagents run the server and monitor for errors. Every change is tracked in a [deciduous](https://github.com/durable-creative/deciduous) decision graph — institutional memory that survives across sessions, developers, and time.

Here's what the full flow looks like for a fresh user.

### 1. Start a Session

Every session begins with context recovery:

```
/recover
```

This reads the deciduous decision graph and reconstructs what happened in prior sessions — what was built, what broke, what decisions were made and why. It also audits graph integrity, fixing any orphaned nodes. Without recovery, you're working blind.

### 2. Launch the Subagents

Run `/monitor` to spin up the three-agent pattern. This is one command, but it launches four background processes:

```
/monitor
```

Here's exactly what happens:

**Process 1: Containers** — `docker compose up --build -d` runs as a background Bash task. Builds the Docker images if needed (app, postgres, graph viewer) and starts them in detached mode. The task completes once the containers are up and healthy.

**Process 2: File watcher** — `docker compose watch` runs as a background Bash task. This is a long-running process that watches the host filesystem and syncs changes into the running container. It triggers inotify events inside Docker so Phoenix live reload picks up every file edit — whether from you, a subagent, or the auto-healer. **This must stay running.** If it dies, hot reload stops working.

**Process 3: Log stream** — `docker compose logs -f --tail=0` runs as a background Bash task. Captures all container output to a file that the listener subagent polls. The `--tail=0` means it starts from now, not replaying history.

**Process 4: Listener subagent** — A `general-purpose` Task agent launched with `run_in_background: true`. This is the brain. Every 10 seconds it reads the last 100 lines from the log stream output file and scans for error patterns:

- `** (RuntimeError)`, `** (FunctionClauseError)` — Elixir exceptions
- `CRASH REPORT`, `exited with` — OTP crashes
- `(Postgrex.Error)`, `FATAL` — database errors
- `== Compilation error` — compile failures
- `502`, `503` — service unavailable

Errors are classified by severity. Critical and Error trigger the debug-then-fix cycle immediately. Warnings are tracked and only escalated after 3 occurrences in 60 seconds.

After `/monitor` completes, you get back the task IDs for all four processes. Your session is free — you continue writing code, running tests, reviewing. The subagents work in the background.

To check on monitor status at any time, read the subagent output files or ask: "how's the monitor doing?"

You can also launch the pieces manually:

```bash
make up && make watch    # in one terminal
make logs                # in another
make listen              # or make monitor
```

### 3. Start a Work Transaction

**Every meaningful change starts with `/work`:**

```
/work "Add piece preview to sidebar"
```

This creates a goal node in the decision graph *before* any code is written. The graph captures not just what changed but why. One `/work` = one logical change = one commit. Only trivial one-line typo fixes skip this.

If the ask involves multiple changes, that's multiple transactions:

```
/work "Fix tile contrast"        # goal -> actions -> outcome -> commit
/work "Slow scanner speed 8x"    # separate goal -> actions -> outcome -> commit
```

The `/work` command also creates action nodes before each file edit and outcome nodes after committing. The Edit/Write hooks will block you if no recent action or goal node exists — this is intentional. It ensures every code change is traceable in the graph.

### 4. Design Types First

Before writing implementation, define the types. Types are the contract between modules — they make boundaries visible and composable. When the types are right, the implementation follows naturally.

Start with `@type`, `@typedoc`, `defstruct`, and `@spec`:

- `Eclipse.Game.Piece` defines `@type t` and `@type color` — the contracts other modules consume
- `Eclipse.Game.Board` defines `@type cell` and `@type t` — exposing what a board IS
- `Eclipse.Game.GameState` combines these into a top-level struct with `@type phase`
- `Eclipse.Game.Engine` operates purely on these typed structs via `@spec`

No `.new()` constructors. Elixir structs are data — construct them directly with `%Module{field: value}`. The `defstruct` defaults are the single source of truth.

### 5. Run Quality Checks

Before committing, always run the full quality pipeline:

```bash
make quality
```

This runs in order: compile (warnings-as-errors), credo (strict), tests, dialyzer, improve-elixir (on changed files only, fed credo output), then format. It continues through failures so you see all issues at once.

### 6. Commit and Log

Stage files **explicitly by name** — never `git add .` or `git add -A`:

```bash
git add lib/eclipse/game/engine.ex lib/eclipse_web/live/game_live.ex
git commit -m "feat: add piece preview to sidebar"
```

**Rebase only.** No merge commits. History must be linear. When integrating branches, use cherry-pick or rebase.

Immediately after committing — before doing anything else — log to deciduous:

```bash
deciduous add action "Implemented piece preview" -c 90 --commit HEAD \
  -f "lib/eclipse/game/engine.ex,lib/eclipse_web/live/game_live.ex"
deciduous link <goal_id> <action_id> -r "Implementation"
```

Then add the outcome node and link it back. Never batch this. Never "come back to it." The post-commit hook will remind you, but don't rely on reminders.

### 7. Subagent Work in Worktrees

When launching subagents in git worktrees, the subagent must log to deciduous itself. The main session cannot do it because deciduous auto-tags nodes with the current git branch — logging retroactively from a different branch breaks the graph.

Every subagent prompt that involves commits must include:

```
After committing, log to deciduous immediately:
  deciduous add action "What you did" -c 90 --commit HEAD -f "files,changed"
  deciduous link <parent_id> <new_id> -r "reason"
```

Pass the parent node ID into the subagent prompt so it can link correctly. If the main session creates a goal node (e.g., node 79), tell the subagent: "Link your action to goal 79."

## Debugging and Self-Healing

The system uses **TDD-driven healing**. Whether you're debugging manually or the auto-healer is fixing a runtime error, the process is the same: diagnose root cause, write a failing test that reproduces it, then fix the source to make the test pass.

### The /debug command

When you hit an error — a stacktrace in logs, a compilation failure, a test failure — use `/debug`:

```
/debug ** (KeyError) key :color not found in: %Eclipse.Game.Piece{tiles: [...]}
    (eclipse 0.1.0) lib/eclipse/game/board.ex:45: Eclipse.Game.Board.place_piece/3
    (eclipse 0.1.0) lib/eclipse/game/engine.ex:23: Eclipse.Game.Engine.tick/2
```

`/debug` walks through a structured diagnosis, then drives the fix via TDD:

1. **Parse the error** — extract the exception type, message, crash site, and full call chain
2. **Read the crash site** — the full function body at the top of the stacktrace, plus its `@spec` and `@type`
3. **Trace the call chain** — for each frame, read what arguments were passed and where the data shape diverged from what the code expected
4. **Check types and contracts** — do the caller's output types match the callee's input types? Is a struct field nil where the code assumes it's present?
5. **Identify root cause** — the earliest point where the fix should go, usually NOT the crash site but 1-3 frames down
6. **Write a failing test (RED)** — before touching source, write a test that constructs the exact input from the stacktrace, calls the root cause function, and asserts correct behavior. Run it, confirm it fails.
7. **Fix the source (GREEN)** — make the minimal change that makes the failing test pass. Run the full suite to check for regressions.

The key insight: the crash site is the symptom, not the disease. A `KeyError` on line 45 means something upstream constructed the wrong data shape. The test proves you understand the bug. The fix proves the test is right.

### How auto-healing uses TDD

The listener subagent follows the same protocol. When it detects an error in the Docker logs:

```
1. Parse    → extract exception, stacktrace, call chain
2. Read     → open crash site, read full function body + types
3. Trace    → walk each frame, find where data diverged
4. Diagnose → identify root cause (not symptom)
5. Test     → write failing test reproducing the exact bug (RED)
6. Fix      → minimal source change to make the test pass (GREEN)
7. Verify   → mix compile --warnings-as-errors && mix test (full suite)
8. Watch    → monitor logs 15 seconds to confirm
```

Every auto-heal leaves behind a regression test. If the same bug ever recurs — in a refactor, a dependency update, a new feature — the test catches it immediately. The test suite grows more precise with every error the system encounters.

If the fix doesn't resolve the error, it re-debugs with new information and writes a new test targeting the revised understanding. After two failed attempts, it escalates to you rather than guessing.

### The healing modes

| Command | Mode | When to use |
|---------|------|-------------|
| `/debug <stacktrace>` | Interactive | You have an error and want to understand it. Diagnoses root cause, writes a failing test, proposes fix, waits for you |
| `/heal` | One-shot | App is broken right now. Reads logs, debugs, writes test, fixes, verifies, reports back |
| `/listen` | Continuous | Background watcher. Polls logs every 10s, auto-debugs and auto-fixes via TDD as errors appear |
| `/monitor` | Full stack | Launches containers + watcher + listener. Everything automated, session stays free |

They build on each other: `/monitor` spawns a `/listen`-style agent, which uses `/debug`-style TDD for every error it encounters.

### The feedback loop

```
code change ──► watch syncs to container ──► Phoenix recompiles
                                                    │
                                                    ▼
                                              error in logs?
                                              │           │
                                             no           yes
                                              │           │
                                              ▼           ▼
                                          keep watching   debug: parse → trace → diagnose
                                                                         │
                                                                         ▼
                                                               write failing test (RED)
                                                                         │
                                                                         ▼
                                                            fix source to pass test (GREEN)
                                                                         │
                                                                         ▼
                                                          verify: compile + full test suite
                                                                         │
                                                                         ▼
                                                              deciduous logs everything
                                                                         │
                                                                         ▼
                                                              watch syncs fix to container ...
```

## The Decision Graph

The decision graph is the backbone of this workflow. It records every goal, option, decision, action, and outcome — not just what happened, but why.

### Node flow

```
goal -> options -> decision -> actions -> outcomes
```

- Goals lead to options (possible approaches)
- Options lead to a decision (choosing one)
- Decisions lead to actions (implementation)
- Actions lead to outcomes (results)
- Observations attach anywhere
- Goals never skip to decisions — options must come first

### Rules

Log in real-time, not retroactively. Before you act, log what you're about to do. After it resolves, log the outcome. Connect every node to its parent immediately. Root goals are the only valid orphans.

### Viewing the graph

```bash
make graph    # serves at localhost:3000
```

Each node carries confidence scores, associated files, and timestamps. Observations link to the actions that addressed them. Actions link to outcomes that verify them.

When a new session starts, `/recover` reads this graph and reconstructs full context. The graph survives across sessions, across developers, across time.

## Reference

### Make targets

| Target | What it does |
|--------|-------------|
| `make up` | Build and start containers (`PORT=8080 make up` for custom port) |
| `make watch` | Start file sync for hot reload (run after `make up`) |
| `make down` | Stop everything |
| `make logs` | Tail container logs |
| `make graph` | Start the deciduous decision graph viewer (`GRAPH_PORT=3001 make graph`) |
| `make setup` | Create database and run migrations (first time) |
| `make migrate` | Run pending migrations |
| `make backup` | Dump database to `backups/` |
| `make iex` | IEx shell on the running app |
| `make shell` | Bash shell inside the app container |
| `make compile` | Compile with `--warnings-as-errors` |
| `make test` | Compile + run test suite |
| `make format` | Format the project |
| `make credo` | Run credo in strict mode |
| `make dialyzer` | Run dialyzer for static analysis |
| `make improve` | Run `/improve-elixir` via Claude |
| `make quality` | Full pipeline: compile, credo, test, dialyzer, improve-elixir, format |
| `make heal` | One-shot error diagnosis and fix via Claude |
| `make listen` | Continuous error listener (takes over the session) |
| `make monitor` | Background monitor (subagent, session stays free) |

### Claude skills

| Skill | Purpose |
|-------|---------|
| `/recover` | Rebuild context from decision graph on session start |
| `/work` | Start a tracked work transaction with deciduous |
| `/monitor` | Launch background server + watcher + listener subagents |
| `/listen` | Continuous error listener (foreground) |
| `/heal` | One-shot: diagnose and fix current Docker errors |
| `/debug` | Structured diagnosis: parse stacktrace, trace call chain, find root cause |
| `/build-test` | Compile and run tests |
| `/improve-elixir` | Systematic code quality improvements |
| `/decision` | Manage decision graph nodes and edges |
| `/document` | Generate docs for a file or directory |
| `/sync-graph` | Export graph to GitHub Pages |

## Docker

The app runs in Docker Compose with three services:

- **app** — Phoenix dev server with live reload (Elixir 1.19 / OTP 28). Uses `Dockerfile.dev` which runs `mix phx.server` in dev mode with esbuild/tailwind watchers. Source code is synced in via `docker compose watch`.
- **db** — PostgreSQL 17 with health checks.
- **graph** — Deciduous decision graph viewer. Built from `Dockerfile.graph` (Rust multi-stage build via `cargo install deciduous`). Mounts `.deciduous/` from the host.

Database defaults to `eclipse_dev`. Configurable via `DB_USERNAME`, `DB_PASSWORD`, `DB_HOSTNAME`, `DB_DATABASE` environment variables.

The original `Dockerfile` (prod release) is still available for production deployments.
