# Eclipse

A Phoenix web app. Runs in Docker with hot reload.

## Design Philosophy

### Type-first design

Always start by defining types that expose boundaries and compose into explicit contracts. Before writing implementation, define the `@type`, `@typedoc`, `defstruct`, and `@spec` that describe data flowing through the system. Types are the contract between modules -- they make boundaries visible and composable. When the types are right, the implementation follows naturally.

In practice:
- `Eclipse.Game.Piece` defines `@type t` and `@type color` -- the contracts other modules consume
- `Eclipse.Game.Board` defines `@type cell` and `@type t` -- exposing what a board IS
- `Eclipse.Game.GameState` combines these into a top-level struct with `@type phase`
- `Eclipse.Game.Engine` operates purely on these typed structs via `@spec`

### No OO constructors

Do NOT create `.new()` constructor functions. Elixir structs are data -- construct them directly with `%Module{field: value}`. The `defstruct` defaults are the single source of truth.

## Docker Dev Workflow

**Starting up:**
1. `make up` -- build and start containers (app + postgres)
2. `make watch` -- file sync for hot reload (separate terminal or background)
3. `make setup` -- create DB and run migrations (first time only)

`make watch` is required on macOS because Docker volume mounts don't propagate inotify events. `docker compose watch` syncs files into the container, triggering the filesystem events Phoenix live reload needs.

**Claude subagents:** Always run `make watch` as a background Bash task before dev work. If changes aren't reflecting in the browser, check that watch is active.

**Make targets:**
- `make up` / `make down` -- start/stop containers
- `make watch` -- file sync for hot reload (blocking)
- `make logs` -- tail container logs
- `make quality` -- **always use this** before committing (compile, credo, test, improve-elixir, format)
- `make graph` -- start deciduous graph viewer

## Work Transactions -- ALWAYS USE /work

**Every meaningful unit of work MUST start with `/work "description"`.** A "meaningful unit" is any change a future session would want to understand. Only trivial one-line typo fixes skip this.

### Flow

1. User asks for something (or you identify work)
2. `/work "short description"` -- creates a goal node with verbatim user request
3. Before each file edit, create an action node linked to the goal
4. After completing work, create an outcome node, commit, link with `--commit HEAD`
5. `deciduous sync` to export

### Why

The decision graph is institutional memory. `/work` captures not just what changed but WHY. Future sessions use `/recover` to rebuild context. Without `/work`, changes are invisible.

### Multiple changes = multiple transactions

```
User: "fix the tile contrast and slow down the scanner"

-> /work "Fix light tile contrast"    # goal + actions + outcome + commit
-> /work "Slow scanner speed 8x"     # separate goal + actions + outcome + commit
```

One `/work` = one logical change = one commit.

## Decision Graph

**Log decisions IN REAL-TIME, not retroactively.**

### Commands & Skills

| Command | Purpose |
|---------|---------|
| `/decision` | Add nodes, link edges, sync |
| `/recover` | Rebuild context from graph on session start |
| `/work` | Start work transaction (goal node before implementation) |
| `/document` | Generate docs for a file or directory |
| `/build-test` | Build and run tests |
| `/serve-ui` | Start graph web viewer |
| `/sync-graph` | Export graph to GitHub Pages |
| `/decision-graph` | Build graph from commit history |
| `/sync` | Multi-user sync |
| `/pulse` | Map current design as decisions |
| `/narratives` | Understand system evolution |
| `/archaeology` | Transform narratives into queryable graph |

### Node Flow (CRITICAL)

```
goal -> options -> decision -> actions -> outcomes
```

- Goals lead to options (possible approaches)
- Options lead to a decision (choosing one)
- Decisions lead to actions (implementation)
- Actions lead to outcomes (results)
- Observations attach anywhere
- Goals NEVER lead directly to decisions -- options must come first
- Decision nodes: only create when an option is actually chosen

### Core Rule

```
BEFORE you act   -> Log what you're ABOUT to do
AFTER it resolves -> Log the outcome
CONNECT immediately -> Link every node to its parent
AUDIT regularly   -> Check for missing connections
```

### When to Log

| Trigger | Node Type | Example |
|---------|-----------|---------|
| New feature request | `goal` **with -p** | "Add dark mode" |
| Exploring approaches | `option` | "Use Redux for state" |
| Choosing an approach | `decision` | "Choose state management" |
| About to write code | `action` | "Implementing Redux store" |
| Something worked/failed | `outcome` | "Redux integration successful" |
| Noticed something | `observation` | "Existing code uses hooks" |

### Document Attachments

```bash
deciduous doc attach <node_id> <file_path>
deciduous doc attach <node_id> <file_path> -d "Architecture diagram"
deciduous doc attach <node_id> <file_path> --ai-describe
deciduous doc list                    # all documents
deciduous doc list <node_id>          # for a specific node
deciduous doc show|describe|open|detach <doc_id>
deciduous doc gc                      # remove orphaned files
```

Suggest attachment only when files are directly relevant to a node. Do not aggressively prompt. Files stored in `.deciduous/documents/` with content-hash dedup.

### Verbatim Prompts (CRITICAL)

Prompts must be the EXACT user message, not a summary.

```bash
# BAD -- summary is useless for recovery
deciduous add goal "Add auth" -p "User asked: add login to the app"

# GOOD -- verbatim enables full context recovery
deciduous add goal "Add auth" -c 90 --prompt-stdin << 'EOF'
I need to add user authentication to the app. Users should be able to sign up
with email/password, and we need OAuth support for Google and GitHub. The auth
should use JWT tokens with refresh token rotation.
EOF
```

Capture prompts on: root goal nodes (full request), major direction changes. Not needed on routine downstream nodes -- they inherit context via edges.

### Maintain Connections (CRITICAL)

The graph's value is in its connections, not just nodes.

| When you create... | IMMEDIATELY link to... |
|-------------------|------------------------|
| `outcome` | The action that produced it |
| `action` | The decision that spawned it |
| `decision` | The option(s) it chose between |
| `option` | Its parent goal |
| `observation` | Related goal/action |
| `revisit` | The decision/outcome being reconsidered |

Root `goal` nodes are the ONLY valid orphans.

### Quick Reference

```bash
deciduous add goal "Title" -c 90 -p "User's original request"
deciduous add action "Title" -c 85
deciduous link FROM TO -r "reason"    # DO THIS IMMEDIATELY
deciduous serve                       # live viewer (auto-refresh 30s)
deciduous sync                        # export for static hosting

# Flags: -c (confidence 0-100), -p (prompt), -f (files), -b (branch)
#        --commit <hash|HEAD>, --date "YYYY-MM-DD"
```

### Link Commits (CRITICAL)

After every git commit, log to deciduous **IMMEDIATELY** — before doing anything else. Never batch. Never "come back to it." The post-commit hook exists to enforce this.

```bash
git commit -m "feat: add auth"
deciduous add action "Implemented auth" -c 90 --commit HEAD
deciduous link <goal_id> <action_id> -r "Implementation"
```

### Subagents MUST Log to Deciduous Themselves (CRITICAL)

When launching subagents in git worktrees, **the subagent must log to deciduous from within its worktree**. The main session CANNOT log on behalf of a worktree because deciduous auto-tags nodes with the current git branch. Logging retroactively from a different branch breaks the graph — the entire point is tracing decisions to the branches they happened on.

**Every subagent prompt that involves commits MUST include:**

```
After committing, log to deciduous immediately:
  deciduous add action "What you did" -c 90 --commit HEAD -f "files,changed"
  deciduous link <parent_id> <new_id> -r "reason"
```

Pass the parent node ID into the subagent prompt so it can link correctly. If the main session creates a goal node (e.g., node 79), tell the subagent: "Link your action to goal 79."

### Deployment

```bash
deciduous sync    # creates docs/graph-data.json + docs/git-history.json
```

Then push to GitHub, enable Pages from /docs folder. Live at `https://<user>.github.io/<repo>/`.

Nodes are auto-tagged with the current git branch. Configure in `.deciduous/config.toml`.

### Audit (Before Every Sync)

1. Every outcome links back to its action?
2. Every action links to its decision?
3. No dangling orphans (except root goals)?

### Git Staging -- CRITICAL

**NEVER** use broad staging: `git add -A`, `git add .`, `git commit -am`, `git add *`.

**ALWAYS** stage files explicitly by name: `git add CLAUDE.md lib/eclipse/game.ex`

This prevents committing secrets, binaries, or unintended changes.

### Session Start

```bash
deciduous check-update && deciduous nodes && deciduous edges && deciduous doc list && git status
```

### Multi-User Sync

```bash
deciduous events status              # check sync status
deciduous events rebuild             # apply teammate events (after git pull)
deciduous events checkpoint --clear-events  # compact old events
```

Events auto-emit on add/link/status commands.

## Project Guidelines

- Use `make quality` to verify all changes before committing
- Use `:req` (`Req`) for HTTP requests. Never use `:httpoison`, `:tesla`, or `:httpc`

### Phoenix v1.8

- LiveView templates start with `<Layouts.app flash={@flash} ...>` wrapping all content. `Layouts` is already aliased in `eclipse_web.ex`
- `current_scope` errors mean your routes are in the wrong `live_session` or you forgot to pass `current_scope` to `<Layouts.app>`
- `<.flash_group>` lives in `Layouts` only -- never call it elsewhere
- Use `<.icon name="hero-x-mark" class="w-5 h-5"/>` for icons (from `core_components.ex`). Never use `Heroicons` modules
- Use `<.input>` for form inputs (imported from `core_components.ex`). When overriding classes, no defaults are inherited -- you must fully style the input

### JS & CSS

- Tailwind CSS v4: no `tailwind.config.js`. Uses import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/eclipse_web";

- Never use `@apply` in raw CSS
- Write your own Tailwind components -- no daisyUI
- Only `app.js` and `app.css` bundles exist. Import vendor deps into these files. No external `<script src>` or `<link href>` in layouts. No inline `<script>` tags in templates

### UI/UX

- World-class UI: clean typography, balanced spacing, refined layouts
- Subtle micro-interactions: hover effects, smooth transitions, loading states


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->