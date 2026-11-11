---
name: onboard
description: Fit a project to the user's agent setup — study it, then draft its project profile (kind, issue and merge policy, tracker, session cap, shared resources, orchestration moments) plus any project-side skills or gates, and write only after approval. Use for /onboard, 'onboard this project', 'set this project up for orchestrate'.
argument-hint: "[what to revisit]"
disable-model-invocation: true
user-invocable: true
---

# /onboard — record how this project works with the agent setup

The user's skills are generic: `/issue`, `/closeout`, `/orchestrate`, `/backlog`
and the rest behave the same in every project until a project says otherwise.
`/onboard` studies one project and writes down what is different about it: who
reads its issues, whether work may land on main directly, what its sessions must
not collide on, which of its own skills fit into orchestration. The result is the
project profile, a file of its own that the skills read with `wto profile` when
they need it, plus any project-side additions the user approves. It stays out of
`AGENTS.md`, which every session loads whether or not anyone orchestrates.

Re-run it to revisit a project; `$ARGUMENTS` can name what changed.

The most common failure is inventing policy: guessing that a project allows
direct merges, or making up resource names. Ask what you cannot see. The second
is writing before the user has seen the draft. The third is copying private
details into a public file.

## 1. Where the profile lives

| Finding | Write the profile to |
|---|---|
| `AGENTS.md` is tracked in the repo (`git ls-files AGENTS.md`), or the repo has none | `.agents/profile.md` in the repo. It is a change to the project, made the way the project takes changes. |
| `AGENTS.md` is a symlink into `~/.dotfiles/agent-files/projects/<name>/` (a `dot agent` overlay) | `profile.md` beside the overlay's `AGENTS.md`, never the project. Commit it inside the submodule, which is its own repository; never push it. |
| Only a `CLAUDE.md` | Ask before touching anything; the user may want it migrated to `AGENTS.md` first. |

`wto profile --path` shows a profile that already exists. If `wto profile` says
the profile is still a `## Project profile` section of `AGENTS.md`, move it into
the file above and delete the section from `AGENTS.md`, as part of the draft the
user approves.

## 2. Study the project (read-only)

- **Instructions and docs:** `AGENTS.md`, `README`, `CONTRIBUTING`, issue and
  merge-request templates, CI configuration.
- **Forge:** the remote, the tool that claims it (see the `issue` skill), and
  the repository's visibility (`gh repo view --json visibility`, the Gitea or
  GitLab equivalent). Public visibility means `Kind: public`.
- **Merging:** protected branches, required reviews, a merge-request skill or
  documented review process. Any of these means `Merge to main: review-required`.
- **Project skills** (`.agents/skills/`, `.claude/skills/`, `.opencode/`,
  `.grok/`): which must run from main (releases, anything that pushes main),
  which produce lists of work (triage, audits), which open merge requests.
- **Shared resources:** what two worktrees could collide on: deploy targets and
  dev clusters, databases, fixed ports, emulators, external accounts. Look at
  deploy recipes, compose files, skaffold, scripts.
- **Tracker:** priority and severity labels, milestones.
- **Checks:** what must pass before work is done (justfile, Makefile, package
  scripts, CI). `/closeout` runs what `AGENTS.md` names.
- **Branch naming:** `git branch -a` and recent history.

## 3. Ask what you cannot see

One batch of questions, each with your best guess as the first option:

- Kind: personal, work, or public. A self-hosted remote does not tell you which.
- Whether direct merges to main are allowed, if nothing documents it.
- The session cap.
- A default model or limits for spawned sessions (for example "never below
  opus"), or none to use the `wtc` skill's table.
- Which shared resources need claims, and whether to gate them.
- How the project's main-only and work-producing skills should hook in, when it
  is not obvious.

## 4. Draft everything, write nothing yet

The profile block:

```markdown
# Project profile
- Kind: personal | work | public
- Issue drafts: direct | review
- Merge to main: direct | review-required (<how: e.g. the merge-request skill>)
- Issues: <where they live>; priority: <what marks it>
- Session cap: <n>
- Models: <default and limits | the wtc skill's table>
- Shared resources: <names>; gate: <entry point | none>
- Main-only skills: <names>; work-producing skills: <names>
- Branch naming: <pattern>

### Orchestration moments
- Before a release: <e.g. warn sessions holding deploy claims; releases replace dev deploys>
- After main moves: <…>
- When a side issue arrives: <…>
```

`Issue drafts: direct` only for a personal project that is not public. Leave out
moments with nothing project-specific; [the orchestrate skill's moments.md](../orchestrate/moments.md)
lists them and their defaults.

Then any project-side additions, each with a one-line reason:

- `wto claim define <names>` for the shared resources (stored in the project's
  `.git`, not committed).
- A gate in the deploy entry point, for example in a just recipe:

  ```bash
  wto claim check deploy/api || { echo "take it first: wto claim take deploy/api" >&2; exit 1; }
  ```

- Changes to the project's own skills: a deploy skill that takes and frees its
  claims, a triage skill that files findings with `/issue` so `/backlog` and the
  orchestrator can dispatch them, a main-only skill noting it runs from main.
- A short "before claiming done" checks line in `AGENTS.md`, if it has none.

Show the whole draft and wait.

## 5. Write what was approved

- The profile goes into the file chosen in step 1, replacing an existing
  profile there. Moving a legacy section out of `AGENTS.md` deletes it there and
  leaves the rest of that file as it is.
- Run `wto claim define` if approved.
- Commit the profile where it was written: in the project like any change to
  it, or in the overlay submodule.
- Project code and skill changes follow the project's process: commit them on a
  personal project; on a review-required one, put them on a branch for its
  merge-request flow and leave the merging to the user.

Report what was written where. `/orchestrate` stops offering onboarding once the
profile exists.

## Do not

- Guess a policy or a resource name; ask.
- Write private details (hostnames, account ids, people's names) into a file a
  public repository tracks.
- Touch `~/.dotfiles/ai/`: project specifics belong to the project or its overlay.
