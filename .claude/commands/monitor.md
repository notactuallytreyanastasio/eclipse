# Background Monitor

Launch the continuous error listener as a background subagent so the main session stays free for other work.

## Instructions

### Step 1: Start the log stream

Use the **Bash tool** with `run_in_background: true` to start tailing Docker logs:

```bash
docker compose logs -f --tail=0 2>&1
```

Save the task ID and output file path — you'll poll this throughout.

### Step 2: Spawn the listener subagent

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
>    g. Rebuild: `docker compose up --build -d`
>    h. Watch logs for 15 seconds to verify
>    i. Log outcome: `deciduous add outcome "Auto-healed: <summary>" -c 95` (or `"Auto-heal failed: <why>" -c 30`) and link to the action
>
> 5. **Rules:**
>    - Never fix the same error more than twice — print `⚠ LISTENER: Could not auto-heal "<error>". Manual intervention needed.`
>    - Never modify test files to make tests pass
>    - Never delete or weaken error handling
>    - Always verify with `mix compile --warnings-as-errors && mix test` before rebuilding
>    - Do NOT create branches, stage files, or commit. Only modify files.
>    - Log every observation, action, and outcome to deciduous
>
> 6. **Loop forever** — after handling an error (or finding none), sleep 10 seconds and poll again.

Pass the actual output file path from Step 1 into the prompt where `<output_file>` appears.

### Step 3: Confirm to the user

Tell the user:
- The background monitor is running
- Provide the subagent task ID so they can check on it with `Read` on the output file
- Remind them it will auto-heal errors and log to deciduous
- They can continue working normally in this session

### Step 4: Periodic check-in (optional)

If the user asks about monitor status, read the subagent's output file and summarize:
- Whether it's still running
- Any errors detected and actions taken
- Current log activity level

$ARGUMENTS
