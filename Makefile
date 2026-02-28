.PHONY: help up down watch logs heal listen monitor graph setup migrate backup shell iex quality test format credo improve compile

ELIXIRC_OPTS = --warnings-as-errors
APP_CONTAINER = illuminates-app-1

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Docker ---

up: ## Start containers (PORT=8080 make up)
	PORT=$(or $(PORT),4000) docker compose up --build -d

watch: ## Start file sync for hot reload (run after make up)
	docker compose watch

down: ## Stop everything
	docker compose down

logs: ## Tail container logs
	docker compose logs -f

heal: ## Auto-diagnose and fix Docker errors via Claude
	echo "run /heal. Log ALL observations, actions, and outcomes to deciduous as described in the /heal instructions." | claude --dangerously-skip-permissions

listen: ## Continuous error listener — watches logs and auto-heals
	echo "run /listen. Log ALL observations, actions, and outcomes to deciduous as described in the /listen instructions." | claude --dangerously-skip-permissions

monitor: ## Background monitor — listener as subagent, main session stays free
	echo "run /monitor. Log ALL observations, actions, and outcomes to deciduous as described in the /monitor instructions." | claude --dangerously-skip-permissions

graph: ## Start the decision graph viewer (GRAPH_PORT=3001 make graph)
	GRAPH_PORT=$(or $(GRAPH_PORT),3000) docker compose up --build -d graph
	@echo "Decision graph viewer at http://localhost:$(or $(GRAPH_PORT),3000)"

# --- Database ---

setup: ## Create database and run migrations (first-time setup)
	docker compose exec app /app/bin/illuminates eval "Illuminates.Release.setup()"

migrate: ## Run pending migrations
	docker compose exec app /app/bin/illuminates eval "Illuminates.Release.migrate()"

backup: ## Backup the database to backups/
	@mkdir -p backups
	docker compose exec db pg_dump -U postgres illuminates_dev > backups/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Backup saved to backups/"

# --- Shell access ---

iex: ## Open an IEx shell on the running app container
	docker compose exec app /app/bin/illuminates remote

shell: ## Open a bash shell inside the app container
	docker compose exec app /bin/bash

# --- Code quality (local) ---

compile: ## Compile with warnings-as-errors
	mix compile --warnings-as-errors

test: ## Run the test suite
	mix compile --warnings-as-errors && mix test

format: ## Format the project
	mix format

credo: ## Run credo in strict mode
	mix credo --strict

improve: ## Run /improve-elixir via Claude (streaming output)
	echo "run /improve-elixir on the project. Do NOT create branches, stage files, or commit. Only modify files. Log what you did to deciduous: 'deciduous add action \"Improve: <summary>\" -c 85' and 'deciduous add outcome \"<result>\" -c 90' linked to the action." | claude --dangerously-skip-permissions

quality: ## Compile, credo, test, improve-elixir, format (continues on failure)
	@failed=0; \
	echo "==> Compiling (warnings-as-errors)..."; \
	mix compile --warnings-as-errors || failed=1; \
	echo "==> Running credo --strict..."; \
	credo_output=$$(mix credo --strict 2>&1); \
	credo_exit=$$?; \
	echo "$$credo_output"; \
	[ $$credo_exit -ne 0 ] && failed=1; \
	echo "==> Running tests..."; \
	mix test || failed=1; \
	echo "==> Finding changed/new files..."; \
	changed_files=$$(git diff --name-only --diff-filter=ACMR HEAD -- '*.ex' '*.exs' '*.heex' 2>/dev/null; git ls-files --others --exclude-standard -- '*.ex' '*.exs' '*.heex' 2>/dev/null); \
	if [ -n "$$changed_files" ]; then \
		echo "==> Running /improve-elixir on changed files..."; \
		if [ $$credo_exit -ne 0 ]; then \
			echo "Run /improve-elixir on ONLY these changed/new files: $$changed_files. Also fix these credo issues: $$credo_output. Do NOT create branches, stage files, or commit. Only modify files. Log what you did to deciduous: 'deciduous add action \"Quality: fix credo + improve <files>\" -c 85' and 'deciduous add outcome \"<result>\" -c 90' linked to the action." | claude --dangerously-skip-permissions || failed=1; \
		else \
			echo "Run /improve-elixir on ONLY these changed/new files: $$changed_files. Do NOT create branches, stage files, or commit. Only modify files. Log what you did to deciduous: 'deciduous add action \"Quality: improve <files>\" -c 85' and 'deciduous add outcome \"<result>\" -c 90' linked to the action." | claude --dangerously-skip-permissions || failed=1; \
		fi; \
	else \
		echo "==> No changed .ex/.exs/.heex files, skipping improve-elixir."; \
	fi; \
	echo "==> Formatting..."; \
	mix format || failed=1; \
	if [ $$failed -ne 0 ]; then echo "==> Some checks failed."; exit 1; else echo "==> All checks passed."; fi
