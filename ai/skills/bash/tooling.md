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
