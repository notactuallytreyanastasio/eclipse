# Background Monitor

Launch the dev server, file watcher, and error listener as background subagents so the main session stays free for work.

## Instructions

### Step 1: Start the containers

Use the **Bash tool** with `run_in_background: true`:

```bash
docker compose up --build -d 2>&1
```

Wait for it to complete.

### Step 2: Start the file watcher

Use the **Bash tool** with `run_in_background: true`:

```bash
docker compose watch 2>&1
```

This is **required for hot reload**. On macOS, Docker volume mounts don't propagate inotify events. `docker compose watch` syncs files into the container and triggers proper filesystem events that Phoenix live reload detects. Without it, code and CSS changes won't reflect in the browser.

### Step 3: Start the log stream

Use the **Bash tool** with `run_in_background: true`:

```bash
docker compose logs -f --tail=0 2>&1
```

Save the task ID and output file path — the listener subagent will poll this.

### Step 4: Spawn the listener subagent

Use the **Task tool** with `subagent_type: "general-purpose"` and `run_in_background: true` to launch a long-running agent with this prompt:

> You are a continuous error listener for a Phoenix/Elixir Docker app.
>
> Your job is to poll the log output file at `<output_file>` every 10 seconds using the Read tool (read the last 100 lines). On each poll:
>
> 1. **Scan for error patterns:**
>    - `[error]` — Elixir Logger errors
>    - `** (` — Elixir exceptions (RuntimeError, FunctionClauseError, etc.)
>    - `CRASH REPORT` — OTP crash reports
>    - `exited with` — process/container exit
>    - `(Postgrex.Error)` — database errors
>    - `(Ecto.` — Ecto errors
>    - `== Compilation error` — compile failures
>    - `FATAL` — Postgres fatal errors
>    - `502` / `503` — service unavailable
>
> 2. **Ignore noise:** `[info]`, `[debug]`, healthcheck pings, normal request logs
>
> 3. **On error detection — classify severity:**
>    - **Critical** (app down): crashes, FATAL DB errors, container exits
>    - **Error** (degraded): runtime errors, failed requests
>    - **Warning**: one-off errors — wait for 3 occurrences in 60s before acting
>
> 4. **For Critical/Error — auto-heal:**
>    a. Log observation: `deciduous add observation "Listener detected: <error summary>" -c 50`
>    b. Read the stacktrace to find the source file and line
>    c. Read the source file to understand the code
>    d. Apply the fix — edit the file directly
>    e. Log the action: `deciduous add action "Auto-heal: <what>" -c 75 -f "file1.ex,file2.ex"` and link to the observation
>    f. Verify: `mix compile --warnings-as-errors && mix test`
>    g. No need to rebuild — `docker compose watch` will sync the fix automatically
>    h. Watch logs for 15 seconds to verify
>    i. Log outcome: `deciduous add outcome "Auto-healed: <summary>" -c 95` (or `"Auto-heal failed: <why>" -c 30`) and link to the action
>
> 5. **Rules:**
>    - Never fix the same error more than twice — print `⚠ LISTENER: Could not auto-heal "<error>". Manual intervention needed.`
>    - Never modify test files to make tests pass
>    - Never delete or weaken error handling
>    - Always verify with `mix compile --warnings-as-errors && mix test` before considering a fix done
>    - Do NOT create branches, stage files, or commit. Only modify files.
>    - Log every observation, action, and outcome to deciduous
>
> 6. **Loop forever** — after handling an error (or finding none), sleep 10 seconds and poll again.

Pass the actual output file path from Step 3 into the prompt where `<output_file>` appears.

### Step 5: Confirm to the user

Tell the user:
- Containers are up
- File watcher is syncing (hot reload active)
- Log listener is monitoring for errors
- Provide task IDs so they can check output files
- They can continue working normally in this session

### Step 6: Periodic check-in (optional)

If the user asks about monitor status, read the subagent output files and summarize:
- Whether containers, watcher, and listener are still running
- Any errors detected and actions taken
- Current log activity level

$ARGUMENTS
