---
name: onboard
description: Fit a project to the user's agent setup — study it, then draft its project profile (kind, issue and merge policy, tracker, session cap, shared resources, orchestration moments) plus any project-side skills or gates and, outside work projects, the forge labels, and write only after approval. Use for /onboard, 'onboard this project', 'set this project up for orchestrate'.
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

Re-run it to revisit a project; `$ARGUMENTS` can name what changed. A re-run
compares as well as studies: the skills may have changed since the last run and
now suggest more, or different, setup than what was applied (step 4).

The most common failure is inventing policy: guessing that a project allows
direct merges, or making up resource names. Ask what you cannot see. The second
is writing before the user has seen the draft. The third is copying private
details into a public file. The fourth is changing a work project's own files.

## 1. Where the profile lives

A **work** project's files are never changed: everything `/onboard` writes goes
to `~/.dotfiles/agent-files/projects/<project>/profile.md`, whatever the
project's `AGENTS.md` is. `<project>` is the project root's name, the
directory holding the shared git dir (`git rev-parse --git-common-dir`), the
name `dot agent` uses. Commit it inside the submodule; never push it. The kind
is settled in step 3, so until then plan for both rows that could apply.

For every other kind:

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
- **Tracker:** priority and severity labels, milestones. Once the kind is known
  (step 3), and unless it is `work`, compare the forge's labels with
  [the label convention](labels.md). On a work project, leave labels alone.
- **Checks:** what must pass before work is done (justfile, Makefile, package
  scripts, CI). `/closeout` runs what `AGENTS.md` names.
- **Branch naming:** `git branch -a` and recent history.

## 3. Ask what you cannot see

One batch of questions, each with your best guess as the first option:

- Kind: personal, work, or public. A self-hosted remote does not tell you which.
- Whether direct merges to main are allowed, if nothing documents it.
- The session cap.
- Limits on the jobs spawned sessions get (for example "never the small
  job"), or none to use the `wtc` skill's table.
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
- Models: <job limits | the wtc skill's table>
- Shared resources: <names>; gate: <entry point | none>
- Main-only skills: <names>; work-producing skills: <names>
- Branch naming: <pattern>
- Deploy: <the skill or recipe that deploys and verifies | none>
- Onboarded: <date>, dotfiles <short sha of ~/.dotfiles HEAD>

## Orchestration moments
- Before a deploy: <checks for whether now is a good time, e.g. no release running>
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
- Unless the kind is `work`, the label rows from [labels.md](labels.md): keep,
  rename, create, and deletions to tick.

On a work project, leave out every addition that changes the project's files
or its forge (skills, gates, the checks line, labels). List the ones you would
have suggested, so the user can raise them by the project's own process.
`wto claim define` stays: it writes only into the local `.git`.

Show the whole draft and wait.

**When the project was onboarded before** (`wto profile` prints a profile), draft
from scratch as above, as if it were new, then compare the draft with what is in
place: the profile, the claim names (`wto claim define` prints them), the deploy
gate, the project skills' orchestration notes, and (unless the kind is `work`)
the forge's labels against [labels.md](labels.md). If the profile's
`Onboarded:` line names a dotfiles commit, `git -C ~/.dotfiles log --oneline
<sha>..HEAD -- ai/skills ai/rules bin/wto` lists what changed in the skills
since. Show only the differences, each with a one-line reason:

- what the skills now ask for that is missing (a new field or moment, a new
  location for the profile);
- project facts that changed (a new deploy target, a renamed skill, a new check);
- setup applied before that the skills no longer recommend.

Keep the user's earlier decisions (kind, policies, cap, models) unless the
answer would change them; ask rather than overwrite. If nothing differs, say so
and write nothing.

## 5. Write what was approved

- The profile goes into the file chosen in step 1, replacing an existing
  profile there. Moving a legacy section out of `AGENTS.md` deletes it there and
  leaves the rest of that file as it is.
- Set the profile's `Onboarded:` line to today and `git -C ~/.dotfiles rev-parse
  --short HEAD`, on a re-run too.
- Run `wto claim define` if approved.
- Apply the approved label changes as [labels.md](labels.md) describes.
- Commit the profile where it was written: in the project like any change to
  it, or in the overlay submodule (always, on a work project).
- Project code and skill changes follow the project's process: commit them on a
  personal project; on a review-required one, put them on a branch for its
  merge-request flow and leave the merging to the user.

Report what was written where. `/orchestrate` stops offering onboarding once the
profile exists.

## Do not

- Guess a policy or a resource name; ask.
- Create, rename, or delete labels on a work project, or any label the user did
  not approve in the draft.
- Write private details (hostnames, account ids, people's names) into a file a
  public repository tracks.
- Touch `~/.dotfiles/ai/`: project specifics belong to the project or its overlay.
- Write, stage, or commit anything in a work project's tree.
