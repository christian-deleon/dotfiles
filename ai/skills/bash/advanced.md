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
