# Label convention

Personal and public projects share one label scheme, so `/issue`, `/backlog` and
the user read the same labels everywhere. Work projects are left alone: no study,
no suggestions, no changes.

## The scheme

Scoped labels, `<scope>/<value>`, lowercase, values hyphenated. One color per
scope, so a glance at an issue list shows the kind of each label.

| Scope | Values | Exclusive | Color |
|---|---|---|---|
| `type/` | `bug`, `feature`, `docs`, `chore` | yes | `#1f6feb` |
| `priority/` | `critical`, `high`, `medium`, `low` | yes | `#b60205`, `#d93f0b`, `#fbca04`, `#c2e0c6` |
| `status/` | `needs-info`, `blocked` | yes | `#8250df` |
| `area/` | the project's own, see below | no | `#0e8a16` |

Each label gets a one-line description of when to use it.

Exclusive means an issue carries at most one label of that scope. Gitea enforces
it (the `exclusive` flag on a scoped label); GitHub and GitLab do not, so it is
only a convention there. `/backlog` ranks on `priority/` and skips `status/`
issues.

**Area labels** are what is unique to the project: the parts an issue gets filed
against, such as its services, packages, deploy targets or subsystems. Take them
from the project's structure and its existing issues, not one per directory;
three to eight is typical. A small project may need none.

## Compare with what the forge has

List the labels with their ids, colors and issue counts, then sort each into one
row of the draft:

| Finding | Draft row |
|---|---|
| Already matches the scheme | keep |
| Same meaning, other name (`bug`, `enhancement`, `P1`, `priority: high`, `frontend`) | rename to the scheme's name. Renaming edits the label in place, so its issues keep it. Never delete and recreate. |
| Two existing labels with one meaning (`bug` and `defect`) | ask which one to rename; the other stays until the user decides |
| A label the scheme has no place for | keep, and say so |
| Unused (no issues) and covered by the scheme | offer to delete, as its own row the user ticks |
| A scheme label the forge lacks | create |

Areas the project would benefit from go in as create rows with a one-line reason
each.

## Apply what was approved

Rename first, then create, then the deletions the user ticked.

| Forge | Create | Rename / recolor | Delete |
|---|---|---|---|
| Gitea | `gitea` MCP `label_write`, `create_repo_label`, with `exclusive: true` for exclusive scopes (`tea labels create` cannot set it) | `update_repo_label` by id | `delete_repo_label` by id |
| GitHub | `gh label create <name> --color <hex> --description <d>` | `gh label edit <old> --name <new> --color <hex>` | `gh label delete <name> --yes` |
| GitLab | `glab label create --name <n> --color <#hex> --description <d>` | `glab label edit` | `glab label delete <name>` |

`gh` takes the color without `#`.
