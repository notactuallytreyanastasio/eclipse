# Continuous Error Listener

Long-running monitor that watches Docker container logs and automatically heals errors as they appear.

## Instructions

### Step 1: Start log monitoring

Launch a background Bash agent to tail Docker logs continuously:

```bash
docker compose logs -f --tail=0 2>&1
```

Use `run_in_background: true` so it streams indefinitely.

### Step 2: Enter the watch loop

Poll the background task output every 10 seconds using the Read tool on the output file (or `tail -20` via Bash). On each check:

1. Read the latest log lines since last check
2. Scan for error-level patterns:
   - `[error]` — Elixir Logger errors
   - `** (` — Elixir exceptions (RuntimeError, FunctionClauseError, etc.)
   - `CRASH REPORT` — OTP crash reports
   - `exited with` — process/container exit
   - `(Postgrex.Error)` — database errors
   - `(Ecto.` — Ecto errors (constraint, migration, query)
   - `== Compilation error` — compile failures
   - `FATAL` — Postgres fatal errors
   - `502` / `503` — service unavailable
3. Ignore noise: `[info]`, `[debug]`, healthcheck pings, normal request logs

If no errors found, continue to next poll cycle.

### Step 3: On error detection — triage

When an error is detected:

1. **Log observation to deciduous:**
   ```bash
   deciduous add observation "Listener detected: <error summary>" -c 50
   ```

2. **Classify severity:**
   - **Critical** (app down): crashes, FATAL DB errors, container exits → fix immediately
   - **Error** (degraded): runtime errors, failed requests → fix immediately
   - **Warning** (watch): one-off errors that may self-resolve → wait for 2 more occurrences before acting

3. **For warnings**: Note the error and continue watching. If it repeats 3+ times within 60 seconds, escalate to Error.

### Step 4: Auto-heal

For Critical and Error severity:

1. **Log the action:**
   ```bash
   deciduous add action "Auto-heal: <what you're fixing>" -c 75 -f "file1.ex,file2.ex"
   deciduous link <observation_id> <action_id> -r "Listener auto-heal"
   ```

2. **Read the stacktrace** to identify the source file and line
3. **Read the source file** to understand the code
4. **Apply the fix** — edit the file directly
5. **Verify locally:**
   ```bash
   mix compile --warnings-as-errors && mix test
   ```
6. **Rebuild the container:**
   ```bash
   docker compose up --build -d
   ```

Do NOT create branches, stage files, or commit. Only modify files.

### Step 5: Verify the fix

After rebuild:

1. Watch logs for 15 seconds to see if the error recurs
2. **Log outcome to deciduous:**
   ```bash
   # If resolved:
   deciduous add outcome "Auto-healed: <summary>" -c 95
   deciduous link <action_id> <outcome_id> -r "Fix verified by listener"

   # If still broken:
   deciduous add outcome "Auto-heal failed: <why>" -c 30
   deciduous link <action_id> <outcome_id> -r "Fix did not resolve"
   ```
3. If the same error appears again after fix, do NOT retry the same fix. Log a second failed outcome and **alert the user** by printing a clear message:
   ```
   ⚠ LISTENER: Could not auto-heal "<error>". Manual intervention needed.
   ```
   Then continue watching for other errors.

### Step 6: Continue watching

After handling an error (or deciding not to), resume the poll loop from Step 2. Keep watching indefinitely until interrupted.

**Important behavioral rules:**
- Never fix the same error more than twice — escalate to user
- Never modify test files to make tests pass — fix the source code
- Never delete or weaken error handling to silence errors
- Always verify with `mix compile --warnings-as-errors && mix test` before rebuilding
- Log every observation, action, and outcome to deciduous

$ARGUMENTS
