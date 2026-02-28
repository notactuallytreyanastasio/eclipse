# Self-Healing Server Monitor

Monitor the Docker containers, diagnose errors, fix them, and restart.

## Instructions

### Step 1: Launch the server monitor

Start a background subagent that runs `make up && make logs` to capture live container output. Use the Task tool with `run_in_background: true` and `subagent_type: "Bash"` to run:

```bash
docker compose up --build -d 2>&1 && docker compose logs -f --tail=100 2>&1
```

### Step 2: Check for errors

Read the background task output periodically. Look for:

- **Elixir/Erlang crashes**: `** (EXIT)`, `** (RuntimeError)`, `** (FunctionClauseError)`, `CRASH REPORT`
- **Phoenix errors**: `[error]`, `(Phoenix.Router.NoRouteError)`, `(Plug.Conn.AlreadySentError)`
- **Ecto/DB errors**: `(Postgrex.Error)`, `(Ecto.ConstraintError)`, migration failures
- **Startup failures**: `exited with status`, `restart loop`, container exit codes
- **Compilation errors**: `== Compilation error`, `undefined function`, `module not found`
- **Asset build errors**: `esbuild`, `tailwind`, bundle failures

### Step 3: Diagnose and log to decision graph

When an error is found:

1. Extract the full error message and stacktrace
2. Identify the file and line number from the stacktrace
3. Read the relevant source file(s)
4. Determine the root cause — is it a code bug, missing migration, config issue, dependency problem?
5. **Log the observation to deciduous:**
   ```bash
   deciduous add observation "Error detected: <brief description>" -c 50
   ```

### Step 4: Fix it

1. **Log the action to deciduous:**
   ```bash
   deciduous add action "Fix: <brief description of fix>" -c 75 -f "file1.ex,file2.ex"
   deciduous link <observation_id> <action_id> -r "Fixing detected error"
   ```

2. Apply the fix directly:
   - **Code bugs**: Edit the source file to fix the issue
   - **Missing migrations**: Run `mix ecto.gen.migration` and write the migration
   - **Config issues**: Fix the config file
   - **Dependency issues**: Update mix.exs and run `mix deps.get`

Do NOT create branches, stage files, or commit. Only modify files.

### Step 5: Rebuild and verify

After fixing:

1. Run `mix compile --warnings-as-errors` locally to verify the fix compiles
2. Run `mix test` to make sure nothing is broken
3. If `docker compose watch` is running, the fix will sync automatically. If not, rebuild: `docker compose up --build -d`
4. Tail the logs again to verify the error is resolved: `docker compose logs -f --tail=50`

### Step 6: Log outcome and report

1. **Log the outcome to deciduous:**
   ```bash
   # If fixed:
   deciduous add outcome "Fixed: <what was resolved>" -c 95
   deciduous link <action_id> <outcome_id> -r "Fix verified"

   # If still broken:
   deciduous add outcome "Fix attempt failed: <why>" -c 30
   deciduous link <action_id> <outcome_id> -r "Fix did not resolve"
   ```

2. Summarize what happened:
   - What error was detected
   - What the root cause was
   - What files were changed
   - Whether the fix resolved the issue

If the error persists after the fix, go back to Step 3 and try again. Maximum 3 fix attempts before asking the user for help.

$ARGUMENTS
