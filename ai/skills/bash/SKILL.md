---
name: bash
description: Modern Bash scripting — safe, idiomatic, lint-clean. ALWAYS use when editing `*.sh`, `*.bash`, files with a `#!/usr/bin/env bash` or `#!/bin/bash` shebang, anything under `bin/`/`scripts/`, `.bashrc`/`.bash_profile`/`.zshrc` fragments that share shell idioms, or for prompts mentioning bash, shell scripting, `set -e`, shebang, shellcheck, shfmt, bats, or 'write a script', 'fix this script', 'add a function', 'parse these args', 'why is my bash broken'. Defaults to bash 4+; calls out POSIX `sh` only when the target is `/bin/sh` (Alpine, dash, init). Enforces shellcheck-clean output, shfmt formatting, and the modern strict-mode synthesis (turn on `set -Eeuo pipefail` AND write code that's correct without it).
compatibility: opencode
---

# Bash Scripting

Bash is glue. It's great for invoking other programs in sequence and gluing their I/O together; it's bad at structured data, concurrency, and anything resembling business logic. When you reach for an associative array of associative arrays, switch languages. Rule of thumb: ~a few hundred lines, complex data, error-recovery semantics, or real string parsing → Python / Go / Rust.

The most common AI failure mode is writing 2005-era bash: unquoted variables, `for f in $(ls)`, useless `cat`, backticks, `function foo()`, `local x=$(cmd)` masking the substitution's exit code, missing `--` before user paths, and `set -e` boilerplate copy-pasted with no understanding of where it lies to you. Don't do that.

## Header / preamble

Every script that is an executable (lives under `bin/`, has `+x`, is run directly) starts the same way:

```bash
#!/usr/bin/env bash
# brief one-line description of what this does
#
# Usage: foo [-v] <input>
set -Eeuo pipefail
shopt -s inherit_errexit nullglob
IFS=$'\n\t'
```

- **`#!/usr/bin/env bash`** finds bash via `$PATH` — works on macOS (Homebrew bash 5.x) and Linux. Use `#!/bin/bash` only in tightly controlled environments where the path is guaranteed or in SUID contexts (and never set the SUID bit on shell scripts anyway).
- **macOS ships bash 3.2** (2007, license-frozen). If a script uses bash 4+ features (`mapfile`, `${var,,}`, `declare -A`, `&>>`, `coproc`), gate it: `((BASH_VERSINFO[0] >= 4)) || { echo "bash 4+ required" >&2; exit 1; }`.
- **POSIX `sh`** only when the target shell is `/bin/sh` — Alpine's ash, Debian/Ubuntu's dash, init scripts, minimal containers, portable installers. Then drop `[[ ]]`, `(( ))`, arrays, `local`, `${var,,}`, process substitution, and pick `#!/bin/sh`. Otherwise commit to bash and use its features.

**Sourced libraries** (`lib/common.sh`) do *not* set strict-mode flags — they pollute the caller. Document the bash version they need with `((BASH_VERSINFO[0] >= 4)) || return` at the top.

## Strict mode (and where it lies to you)

The pragmatic 2024+ synthesis: turn on `set -Eeuo pipefail; shopt -s inherit_errexit` **and** still write code that would be correct without them. Treat strict mode as a smoke detector, not a sprinkler.

| Flag | Does |
|---|---|
| `-e` (`errexit`) | Exit on any unhandled non-zero status |
| `-u` (`nounset`) | Error on unset variable references — use `${var-}` to opt out |
| `-o pipefail` | A pipeline's exit status is the last non-zero stage's |
| `-E` (`errtrace`) | `ERR` traps fire inside functions, subshells, command substitutions |
| `shopt -s inherit_errexit` (4.4+) | Subshells inherit `-e`. Without it, `x=$(false; echo ok)` does not abort |
| `shopt -s nullglob` | Globs matching nothing expand to empty, not the literal pattern |
| `IFS=$'\n\t'` | Removes space from word-splitting (still no excuse to skip quoting) |

**`set -e` is silently disabled** in:
- the condition of `if`, `while`, `until`, `&&`, `||` (except the final command in a chain)
- any command on the left of a pipe (so always pair with `-o pipefail`)
- command substitutions, before bash 4.4 / without `inherit_errexit`
- functions called in any of the above

**Common bite-ables:**

```bash
local x=$(cmd)            # -e does NOT fire on cmd failure; local's exit status hides it.
local x; x=$(cmd)         # Correct: separate declaration from assignment.

(( i++ ))                 # When i==0, the expression is 0 → exit status 1 → -e fires.
(( ++i )) || true         # Or: i=$((i+1))

x=$(grep foo file)        # grep returning "no match" (status 1) aborts the script under -e.
x=$(grep foo file) || true   # Tolerate the no-match case explicitly.

set +e; cmd; rc=$?; set -e   # Capture a status without aborting.
killall myapp || true         # Or simply `|| true` if you don't need the code.
```

If you find yourself writing `|| true` more than twice, the code is fighting `-e`. Switch to an explicit `if cmd; then …`.

## Error handling & cleanup

A `die()` helper and trap pair is standard kit:

```bash
die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

tmp=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf -- "$tmp"' EXIT
trap 'die "line $LINENO: $BASH_COMMAND failed (exit $?)"' ERR
```

- **Stderr for all diagnostics.** Stdout is for the script's actual output so the user can pipe it.
- **`trap … EXIT`** fires on normal exit, errors, and untrapped signals — register it *immediately after* allocating the resource so partial-init still cleans up.
- **Traps don't cross subshells.** Re-register inside a subshell if it allocates resources.
- **`mktemp -d`** for tempdirs — creates with mode 0700, names are unpredictable. Never `/tmp/foo.$$` (predictable, symlink-attack vector).
- **`sudo` and redirection:** `sudo cmd > /protected` redirects in the *unprivileged* shell. Use `sudo tee /protected >/dev/null` or `sudo sh -c 'cmd > /protected'`.

## Variables & quoting

The Big Rule: **quote every expansion** unless you have a specific reason not to. ShellCheck SC2086 is non-negotiable.

```bash
# Bad
rm $file                  # word-splits, globs, missing --
[ $var = foo ]            # empty $var crashes [
local x=$(cmd)            # masks cmd's exit status

# Good
rm -- "$file"
[[ $var == foo ]]
local x; x=$(cmd)
```

Other rules:

- **`${var}`** braces consistently — required when adjacent to text: `"${var}_suffix"`.
- **`local`** every function-scoped variable. Bash variables are global by default.
- **`readonly`** for module-level constants; `declare -r` inside functions.
- **`declare -A`** for associative arrays (bash 4+); **`declare -a`** for indexed arrays (often optional but explicit is fine).
- **`--`** before user-supplied paths on every command that takes options: `rm -- "$file"`, `cp -- "$src" "$dst"`, `grep -- "$pattern" "$file"`.

Parameter expansion — prefer over forking `sed`/`cut`/`awk`:

| Form | Meaning |
|---|---|
| `${var:-default}` | Use `default` if `var` is unset/empty |
| `${var:=default}` | Assign and use `default` if unset/empty |
| `${var:?msg}` | Exit with `msg` if unset/empty (great for required args) |
| `${var:+alt}` | `alt` if `var` is set and non-empty |
| `${var#prefix}` / `${var##prefix}` | Strip shortest/longest prefix |
| `${var%.ext}` / `${var%%pat}` | Strip shortest/longest suffix |
| `${var/pat/repl}` / `${var//pat/repl}` | Replace first/all (no regex; glob patterns) |
| `${var^^}` / `${var,,}` | Upper/lower case (bash 4+) |
| `${#var}` | Length |
| `${var:offset:length}` | Substring |
| `${arr[@]:offset:length}` | Array slice |

## Control flow

- **`[[ … ]]`** over `[ … ]`. No word-splitting on the LHS, no globbing surprises, supports `=~` regex, `&&`/`||`, and pattern matching on the RHS.
- **`(( … ))`** for arithmetic and integer comparison. `(( a < b ))`, not `[[ "$a" -lt "$b" ]]`.
- Inside `[[ $x = pattern ]]`, **don't quote the right side** if you want pattern matching; **quote** if you want a literal. For regex put it in a variable:

  ```bash
  re='^[0-9]+$'
  [[ $x =~ $re ]] || die "not a number: $x"
  ```

- **`case`** over chained `elif` for string dispatch.
- **`IFS= read -r line`** always — `-r` stops backslash mangling, leading `IFS=` preserves whitespace.
- **Null-delimited file iteration** is the safe pattern for arbitrary filenames:

  ```bash
  while IFS= read -r -d '' file; do
      process -- "$file"
  done < <(find . -type f -print0)
  ```

## Functions

```bash
greet() {                      # POSIX form. Never `function greet`, never `function greet()`.
    local name=${1:?name required}
    local greeting=${2:-hello}
    printf '%s, %s\n' "$greeting" "$name"
}

main() {
    greet "$@"
}

main "$@"                      # Run only when executed directly, source-able otherwise.
```

- Snake_case names; optional `mypkg::fn` namespacing for libraries.
- **`local` on every** function-scoped variable. The #1 source of cross-function bugs is forgetting one.
- **Returning values:**
  - **Predicate** → exit code (`return 0` / `return 1`); call with `if greet …; then`.
  - **String / scalar** → print to stdout, capture with `x=$(greet …)`.
  - **Complex / multiple** → nameref into caller's variable:

    ```bash
    parse_url() {
        local -n _scheme=$1 _host=$2 _path=$3
        local url=$4
        _scheme=${url%%://*}
        _host=${url#*://}; _host=${_host%%/*}
        _path=/${url#*://*/}
    }

    parse_url scheme host path "https://example.com/api/v1"
    ```

- Put the entry point at the bottom: `main "$@"`. Guard with `[[ ${BASH_SOURCE[0]} == "$0" ]] && main "$@"` if the script is also sourced by tests.

## External commands & file iteration

- **Prefer builtins over forks**: parameter expansion over `sed`/`cut`, `(( ))` over `expr`, `[[ =~ ]]` over `grep` for simple matches, `printf` over `echo`.
- **`command -v foo`** to test for a command — not `which` (non-standard, inconsistent exit codes).
- **Never parse `ls`**. Use globs (`for f in ./*.txt`, with `nullglob` so it doesn't loop on the literal `*.txt`) or `find … -print0 | xargs -0` / `find … -exec cmd {} +`.
- **`mapfile`** / **`readarray`** (bash 4+) for reading lines into an array — fed by process substitution so the array survives:

  ```bash
  mapfile -t lines < <(grep -h pattern file*.log)
  printf '%d lines\n' "${#lines[@]}"
  ```

- **No useless `cat`.** `grep pat file`, not `cat file | grep pat`. To load a file into a variable: `var=$(<file)`, not `var=$(cat file)`.
- **`printf`** over `echo`. `echo` flags (`-e`, `-n`) are non-portable, and `echo "$x"` mangles input starting with `-`. `printf '%s\n' "$x"` always works.

## Pipes & subshells

The classic trap:

```bash
count=0
ls | while read -r f; do
    (( count++ ))
done
echo "$count"                  # Always 0 — the `while` ran in a subshell.

# Fix with process substitution:
count=0
while IFS= read -r f; do
    (( count++ ))
done < <(ls)
echo "$count"                  # Correct.
```

- **`<(cmd)`** / **`>(cmd)`** keep both sides in the current shell. Use to feed `while read` loops and `mapfile`.
- **`PIPESTATUS[@]`** array exposes per-stage exit codes when `pipefail` isn't enough detail.
- **`shopt -s lastpipe`** + a non-interactive shell runs the last pipeline stage in the current shell — useful but niche; process substitution is the broadly-understood idiom.

## Argument parsing

**Short options only** → built-in `getopts` (POSIX, no fork):

```bash
verbose=0
output=
while getopts ':vo:h' opt; do
    case $opt in
        v) verbose=1 ;;
        o) output=$OPTARG ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG requires an argument" ;;
        \?) die "unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
```

**Long options (`--foo`, `--foo=bar`)** → hand-rolled `case` loop (more readable than GNU `getopt` in most cases):

```bash
verbose=0; file=
while (( $# )); do
    case $1 in
        -h|--help) usage; exit 0 ;;
        -v|--verbose) verbose=1 ;;
        --file=*) file=${1#*=} ;;
        --file) file=$2; shift ;;
        --) shift; break ;;
        -*) die "unknown flag: $1" ;;
        *) break ;;
    esac
    shift
done
# remaining positionals in "$@"
```

Honor `--` to terminate option parsing before positionals. Skip BSD `getopt` entirely — only GNU `getopt` (util-linux) handles whitespace correctly, and even then a hand-rolled loop is usually clearer.

## Logging & output

```bash
log()  { printf '[%(%FT%T%z)T] %s\n' -1 "$*" >&2; }
warn() { log "WARN: $*"; }
die()  { log "ERROR: $*"; exit 1; }
```

- **Diagnostics → stderr** (`>&2`). Reserve stdout for the script's actual output.
- **`printf` over `echo`.**
- **TTY-aware color:**

  ```bash
  if [[ -t 1 ]] && [[ -z ${NO_COLOR-} ]] && command -v tput >/dev/null; then
      red=$(tput setaf 1); green=$(tput setaf 2); reset=$(tput sgr0)
  else
      red=; green=; reset=
  fi
  ```

  Honor `NO_COLOR` (any value present disables color — [no-color.org](https://no-color.org/) cross-tool convention) and the `-t 1` TTY check. Prefer `tput` over hardcoded `\033[31m` escapes — works across terminfo definitions.

## Security

- **Never `eval` untrusted input.** If you must, generate the string yourself and document why.
- **Word-splitting on attacker-controlled input is command injection.** Quote everything.
- **`find … -exec sh -c '…' _ "{}" \;`** — pass the filename as `$1`, not interpolated into the script body.
- **Atomic writes:** write to a tempfile in the same directory, then `mv`. Rename is atomic on the same filesystem.

  ```bash
  tmp=$(mktemp "$dest.XXXXXX")
  write_output > "$tmp" && mv -- "$tmp" "$dest"
  ```

- **Singleton scripts with `flock`:**

  ```bash
  exec 200>/var/lock/myscript.lock
  flock -n 200 || die "already running"
  ```

- **Safe PATH** at the top of security-sensitive scripts: `PATH=/usr/local/bin:/usr/bin:/bin`.

## Project layout

```
bin/myscript            # shebang, set -Eeuo pipefail, main "$@"
lib/common.sh           # sourced helpers, no shebang, no set -e
test/test_main.bats     # bats-core tests
```

- Put scripts under `bin/`, mark `+x`, **drop the `.sh` extension** for tools in `$PATH` — users shouldn't have to know what language a CLI is written in.
- Libraries get `.sh`, no shebang, no strict-mode at top, and a version guard if they need bash 4+.

## Tooling

| Tool | Role | Notes |
|---|---|---|
| [**shellcheck**](https://www.shellcheck.net/) | Static analysis | Treat as required. Gate CI on it. Disable specific checks inline with `# shellcheck disable=SCxxxx` *plus a justification comment*. |
| [**shfmt**](https://github.com/mvdan/sh) | Formatter | `shfmt -i 2 -ci -bn -s -w` (≈ Google style). Honors `.editorconfig`. |
| [**bats-core**](https://github.com/bats-core/bats-core) | Test framework | The standard. Pair with `bats-assert`, `bats-support`, `bats-mock`. Structure scripts so the body is in functions and `main "$@"` runs only when `[[ ${BASH_SOURCE[0]} == "$0" ]]` — then `bats` can source the script. |
| [**shellharden**](https://github.com/anordal/shellharden) | Auto-quoter | Useful one-shot pass on legacy code before shellcheck. |

ShellCheck inline directives:

```bash
# shellcheck source=lib/common.sh
. ./lib/common.sh

# shellcheck disable=SC2034  # var is exported via `env` in run_app
DEBUG=1
```

## When to stop using bash

Switch languages when you hit any of:

- Structured data beyond a `jq` one-liner
- Concurrency (real, not "run two things with `&`")
- Error recovery / retry semantics that aren't a flat loop
- Complex string parsing (CSV, INI, YAML, anything multi-line)
- More than a few hundred lines, or a deep call graph
- Cross-platform UI / TUI

Bash is a *dispatcher*. If the script's job is "call these N programs in this order, and stop on failure," bash is great. If the script has its own logic, ship Python or Go instead.

## Don't / Do

| Don't | Do |
|---|---|
| `for f in $(ls *.txt)` | `for f in ./*.txt` (with `nullglob`) |
| `for f in $(find …)` | `while IFS= read -r -d '' f; do …; done < <(find … -print0)` |
| `cat file \| grep pat` | `grep pat file` |
| `var=$(cat file)` | `var=$(<file)` |
| `` `cmd` `` (backticks) | `$(cmd)` |
| `[ $var = x ]` (unquoted) | `[[ $var == x ]]` |
| `if [ $? -eq 0 ]; then cmd2` | `if cmd1; then cmd2` |
| `cmd1 && cmd2 \|\| cmd3` as if-else | proper `if/then/else` — `cmd3` also runs when `cmd2` fails |
| `echo -e "$var"` | `printf '%s\n' "$var"` |
| `function foo() { … }` | `foo() { … }` |
| `cd /foo; rm -rf *` | `cd /foo \|\| die "cd failed"; rm -rf -- *` |
| `local x=$(cmd)` | `local x; x=$(cmd)` |
| `read line` | `IFS= read -r line` |
| `sleep 5; check_thing` polling | `timeout` + retry loop with backoff, or signal/file notification |
| `rm $file` | `rm -- "$file"` |
| `eval "$user_input"` | parse explicitly; arrays for argv |
| Counter inside `cmd \| while` | `while … done < <(cmd)` (process substitution) |
| `$*` to iterate args | `"$@"` (or bare `for arg`) |
| `tmp=/tmp/me.$$` | `tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT` |
| `which foo` | `command -v foo` |
| `function foo()` keyword form | `foo()` POSIX form |
| Missing `set -euo pipefail` | `set -Eeuo pipefail; shopt -s inherit_errexit nullglob` |
| Globals everywhere in a function | `local` on every function-scoped variable |
| Hardcoded `\033[31m` color codes | `tput setaf 1` + `-t 1` + `NO_COLOR` checks |
| `sudo cmd > /protected` | `sudo tee /protected >/dev/null` |
| Hand-roll a `usage` mishmash | `getopts` (short) or `case` loop (long); honor `--` |
| Skip shellcheck | shellcheck-clean is the bar, with documented disables only |
