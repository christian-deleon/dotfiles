---
name: just
description: Authoring justfiles for the `just` command runner. Use when editing `justfile`/`*.just`, or for prompts about `just`, recipes, task runners — 'add a build task', 'fix the deploy recipe', 'what does this justfile do', 'refactor this Makefile to just'. Use modern features (modules, attributes, settings, shebang recipes) — never Make-style targets in disguise.
compatibility: opencode
---

# Justfile Authoring

`just` is a command runner — closer to a polyglot script dispatcher than to `make`. Don't translate Make habits over: no tab requirement, no `$@`/`$<` magic vars, no implicit dependency graph, no rebuild-on-mtime semantics. Recipes always run when invoked.

The most common AI failure mode here is writing a justfile that compiles but ignores the last several years of the language: no attributes, no groups, no modules, ad-hoc shell quoting, undocumented recipes. Use the features.

## File layout

A repo grows from a single justfile into a root + modules pattern. Both look the same at the top:

```just
set quiet := true       # don't echo commands; let the command's own output be the output

# Variables (parse-time). Use := always; = is for exports.
op_account := "my.1password.com"
kube_context := "prod-aws"

# Modules — split a large justfile by domain. Each module is its own justfile.
mod ansible 'ansible/justfile'
mod flux 'scripts/flux.just'

[private]
default:
    @just --list --unsorted
```

The `default` recipe runs when you invoke `just` with no args. Make it `[private]` and have it list recipes — that's the universal pattern. `--unsorted` preserves the order you wrote them in (more meaningful than alphabetical).

Module-level groups are set on the `mod` line: `[group('infra')] mod flux 'scripts/flux.just'`. Recipe-level groups go on the recipe.

## Recipes

A recipe is a comment block + signature + body. **The comment above a recipe is its documentation** — `just --list` pulls it. If a recipe has no comment, it's undocumented.

```just
# Configure k3s cluster (server_prepare → swap → firewall → k3s install)
[group('playbook')]
config-k3s inventory='inventories/aws/k3s' *args='':
    ansible-playbook -i {{inventory}}/aws_ec2.yaml playbooks/config_k3s.yml {{args}}
```

Two recipe body styles:

**Linewise** — each line runs in a fresh shell. Use for a single command or a couple of simple ones. State doesn't carry between lines (no shared `cd`, no shared shell vars without `&&`):

```just
fmt:
    cargo fmt --all
    cargo clippy --fix --allow-dirty
```

**Shebang** — entire body runs as one script in the language of the shebang. Use for any non-trivial logic. Always `set -euo pipefail` for bash:

```just
deploy env:
    #!/usr/bin/env bash
    set -euo pipefail
    export TOKEN="$(op item get my-token --fields credential --reveal)"
    kubectl --context {{env}} apply -f manifests/
```

Shebang recipes can be Python, Node, Ruby, anything — they run as that interpreter, not bash:

```just
analyze:
    #!/usr/bin/env python3
    import json, pathlib
    data = json.loads(pathlib.Path('report.json').read_text())
    print(sum(d['cost'] for d in data['items']))
```

## Parameters

Parameters declared on the recipe signature; interpolated into the body with `{{name}}`:

```just
build target='release' +features='':
    cargo build --{{target}} {{ if features != '' { '--features ' + features } else { '' } }}
```

- **Default values**: `param='default'` makes it optional. Quoting is required.
- **Variadic**: `+args` (one or more, error if zero) or `*args` (zero or more).
- **Last-only positional**: only one variadic per recipe and it must be last.

When you genuinely want raw positional args (`$1`, `$2`, `"$@"`) inside a shebang-or-linewise bash recipe, set `set positional-arguments` at the top — `just` will pass them through. Without it, you must use `{{var}}` interpolation.

## Variables and expressions

```just
# Parse-time string
project := "myapp"

# Parse-time command (backticks). Runs once when justfile is parsed.
git_sha := `git rev-parse --short HEAD`

# Runtime command — use $(...) inside the recipe body, NOT backticks
recipe:
    echo "Building at $(date -u +%Y%m%dT%H%M%SZ)"
```

Useful built-in functions (call as `function(...)`):
- `env_var('NAME')`, `env_var_or_default('NAME', 'fallback')`
- `path_exists('./file')`, `absolute_path('x')`, `parent_directory('x')`
- `os()`, `arch()`, `os_family()` — `"macos"` / `"linux"` / `"windows"` etc.
- `clean(path)`, `replace(s, from, to)`, `replace_regex(s, re, to)`, `uppercase(s)`, `lowercase(s)`, `trim(s)`
- `error('msg')` to fail at parse time

Conditionals are expressions, not statements:

```just
target := if env_var_or_default('CI', '') == 'true' { 'release' } else { 'debug' }
```

## Settings (`set`)

Put these at the very top, before recipes. The most useful:

| Setting | When to use |
|---|---|
| `set quiet := true` | Almost always. Stops echoing each command line; the command's own output is plenty. |
| `set dotenv-load := true` | Auto-load `.env` from the justfile's dir or any parent. |
| `set dotenv-required := true` | Fail if `.env` is missing (good for CI). |
| `set dotenv-filename := ".env.local"` | Override the file name. |
| `set positional-arguments := true` | Pass recipe args through as `$1`, `$2`, `"$@"` — needed when a wrapper recipe forwards args to a command verbatim. |
| `set fallback := true` | If a recipe isn't found, look for it in a parent justfile. Useful for nested invocations. |
| `set shell := ["bash", "-cu"]` | Pin the shell. Default uses `sh`; lock to bash if your linewise recipes use bashisms. |
| `set windows-shell := ["pwsh", "-c"]` | Pair with `set shell` when supporting Windows. |
| `set ignore-comments := true` | Keep comments out of recipe execution echo (rarely needed if `quiet` is on). |
| `set tempdir := "/var/tmp"` | Move shebang scratch files off `/tmp` when needed. |

## Attributes

Attributes go on the line above the recipe. Stack as many as you need:

| Attribute | Purpose |
|---|---|
| `[private]` | Hide from `--list`. (Same as prefixing the recipe name with `_`.) |
| `[group('name')]` | Group in `--list` and `--groups` output. Use consistently — pick a small set of group names per justfile. |
| `[doc('text')]` | Override the comment-as-doc with explicit text. Use only when the comment isn't right for the doc string. |
| `[confirm]` / `[confirm("Really?")]` | Prompt before running. Always use for destructive ops (`destroy`, `wipe`, `reset`). |
| `[no-cd]` | Don't `cd` to the justfile's directory before running. Default is to cd. |
| `[no-quiet]` | Override `set quiet := true` for one recipe. Useful for recipes whose echoed commands are themselves the value. |
| `[unix]` / `[linux]` / `[macos]` / `[windows]` | Restrict the recipe to one OS. Multiple recipes with the same name + different OS attrs is the way to do cross-platform. |
| `[script]` / `[script('interpreter', 'arg', ...)]` | Run the body as a single script with the given interpreter. Often a cleaner alternative to a shebang line. |
| `[positional-arguments]` | Per-recipe equivalent of `set positional-arguments`. |
| `[working-directory('path')]` | Run from a specific directory instead of the justfile's. |

## Modules

When a justfile has more than ~15 recipes or covers more than one domain, split with `mod`:

```just
# Root justfile
mod ansible 'ansible/justfile'
mod terraform 'terraform/justfile'
mod flux 'scripts/flux.just'
```

Then `just ansible config-k3s` invokes the `config-k3s` recipe in `ansible/justfile`. `just --list` shows modules as separate sections. Module recipes can themselves include modules, but two levels deep is usually plenty.

`mod foo` (no path) looks for `./foo/justfile`, `./foo.just`, or `./foo`. Be explicit with the path argument when the file isn't at the obvious location.

## Discovery and debugging

```sh
just                       # run the default recipe
just --list                # show all recipes (with their doc comments)
just --list --unsorted     # in declaration order — usually more useful
just --groups              # show groups
just --show <recipe>       # show the recipe body and resolved attributes
just --evaluate            # print all variables and their resolved values
just --evaluate VAR        # print one variable
just --dry-run <recipe>    # show what would run without running it
just --fmt --unstable      # auto-format the justfile
```

`just --fmt --unstable` is worth running before commit. It's stable in practice; the `--unstable` flag is just gating.

## Don't / Do

| Don't | Do |
|---|---|
| Tab-indent like Make (just doesn't require tabs; mixed indentation breaks parsing) | Use 4 spaces consistently |
| Long bash one-liner with `&& \` continuations | Shebang recipe with `set -euo pipefail` |
| Undocumented recipes | Comment immediately above each recipe (auto-becomes `--list` doc) |
| Flat justfile with 40 recipes | Split via `mod` once it's hard to scan |
| `[group(setup)]` (bareword) | `[group('setup')]` (quoted) |
| Hand-roll arg-forwarding with `{{args}}` everywhere | `set positional-arguments` + `"$@"` in a shebang body |
| Hardcode secrets in variables | `env_var_or_default` + `.env` (with `set dotenv-load`) or pull from a secrets manager in the recipe body |
| `default:` running the whole build | `[private] default:` calling `just --list --unsorted` |
| Destroy/reset recipes that just run | `[confirm("...")]` on anything irreversible |
| Use `=` for variables | `:=` for variables; `=` only on `export NAME = value` |
| Name internal helpers like public recipes | `_internal-helper` or `[private]` |
| Forget `set shell` then ship to a system without bash | `set shell := ["bash", "-cu"]` if you use bashisms in linewise recipes |
| Repeat the same env-var dance in every recipe | Hoist into a parse-time variable or shared shebang preamble |
