---
name: issue
description: File an issue in the current repo's own tracker (GitHub, Gitea, GitLab) from the conversation. Use for /issue, 'make an issue for this', 'track this for later', 'this is too big, file it', or 'split this into issues'. Detects the forge from the git remote and uses its CLI. Checks for duplicates; drafts first unless the project profile says direct.
argument-hint: "[what to track | split: <effort>] (empty = from context)"
user-invocable: true
---

# /issue — capture work as an issue in this repo's tracker

The user is mid-conversation and wants something parked: an unrelated bug that
surfaced, an effort that turned out too large for this session, or a big effort
to break into trackable pieces. The job is to turn that context into a
self-contained issue a future session (or the user, weeks later) can pick up
cold, and file it in **the tracker the repo already uses**, through the tool
whose credentials are already set up.

The most common failure is reaching for the HTTP API (curl plus a token) or
asking the user for credentials. Don't: the user has a CLI logged in for every
forge they use. A second failure is an issue that only makes sense with this
chat open ("fix the thing we discussed"). A third is filing against the wrong
remote — a fork's `origin` instead of `upstream`, or a mirror.

## 1. Find the forge and repo

```bash
git remote -v
```

- Use `origin` by default. If there is also an `upstream` (or several remotes on
  different hosts) and it's unclear where issues belong, ask — one question.
- Parse host and `owner/repo` (GitLab may nest: `group/subgroup/repo`) from the URL (SSH `git@host:owner/repo.git`,
  `ssh://git@host:port/owner/repo.git`, or HTTPS).
- No remote → stop and say so. Don't create the repo.

## 2. Pick the tool

Match the host against what's installed and logged in. Check, don't assume — a
self-hosted host name tells you nothing until a CLI claims it.

| Forge | Detect | Tool |
|---|---|---|
| GitHub (github.com or Enterprise) | host is `github.com`, or listed in `gh auth status` | `gh` |
| Gitea / Forgejo | host matches a URL or SSH host in `tea logins list` | `gitea` MCP server if this session has it (per the `gitea` rule), else `tea` |
| GitLab (gitlab.com or self-hosted) | host is `gitlab.com`, or listed in `glab auth status` | `glab` |

If no CLI claims the host, stop and tell the user which CLI to install or log
into (`gh auth login`, `tea login add`, `glab auth login --hostname <host>`).
Do not fall back to raw API calls or go looking for tokens. If the Gitea host
doesn't respond, follow the `gitea` rule (likely a VPN/Netbird disconnect —
tell the user, don't retry).

## 3. Read the repo's conventions (read-only)

- **Issue templates:** `.github/ISSUE_TEMPLATE/`, `.gitea/ISSUE_TEMPLATE/`,
  `.gitlab/issue_templates/`. If one fits, follow its sections.
- **Labels:** list existing labels and use only ones that clearly fit. Never
  create labels.

| Tool | Labels |
|---|---|
| `gh` | `gh label list -R owner/repo` |
| `tea` | `tea labels list --login <name> --repo owner/repo` |
| `glab` | `glab label list -R owner/repo` |

## 4. Check for an existing issue

Before drafting anything new, search the tracker — open **and** closed. One
keyword search misses rewordings, so run several: the distinctive nouns, the
file or component name, and the exact error text if there is one. Open the
best few hits and read their bodies, not just titles. For a split, check each
piece as well as the overall effort.

| Tool | Search (all states) | Read one |
|---|---|---|
| `gh` | `gh issue list -R owner/repo --state all --search "<terms>"` | `gh issue view <n> -R owner/repo --comments` |
| `tea` | `tea issues list --login <name> --repo owner/repo --state all --keyword "<terms>"` | `tea issues <n> --login <name> --repo owner/repo --comments` |
| `glab` | `glab issue list -R owner/repo --all --search "<terms>"` | `glab issue view <n> -R owner/repo --comments` |
| `gitea` MCP | the issue search / list tools | the issue read tool |

Classify what you find:

| Finding | Meaning | Action |
|---|---|---|
| **Duplicate** | An **open** issue about the same problem or goal — fixing one would close the other | Don't file a new one. Update the existing issue (below); no need to ask which. |
| **Similar** | Overlapping but not the same: same area with a different symptom, a broader or narrower scope, or a **closed** issue about the same thing | Show it and ask: update that issue (or reopen it, if closed) or file a new one? A new one should link the related issue. |
| **Nothing close** | — | Draft a new issue. |

When unsure whether it's a duplicate or merely similar, treat it as similar
and ask.

**Updating** means adding a comment with what this conversation adds — new
findings, a fresh reproduction, file locations, a changed scope. Don't rewrite
the existing body. If the existing issue already covers everything, add
nothing; just tell the user it's already tracked and give the link.

## 5. Draft

Write for a reader with no access to this conversation. Pull concrete facts
from the session; don't pad with what wasn't established.

Issues aren't only problems. Decide the type first — **bug**, **feature**,
**task** (refactor, cleanup, upgrade, docs), or **tracking** (parent of a
split) — then read [templates.md](templates.md) for that type's sections,
title shape, and label. A repo's own template from step 3 wins. Ask only if
the type is genuinely unclear and would change the shape of the issue.

Drop sections that would be empty. Titles are specific, never "Auth issue" or
"Improvements".

Never include secrets, tokens, internal hostnames from other projects, or
pasted chat transcript. On a public repo, also leave out anything the user
treated as private in the conversation.

**Splitting a large effort:** draft one parent (tracking) issue with the goal
and a checklist, plus one child issue per piece. Each child must stand alone
and say what it depends on. Cut along real seams (separately shippable or
reviewable), not by file. Don't invent pieces the conversation didn't support —
list open questions in the parent instead.

For an update to an existing issue, draft only the comment: what's new since
the issue was written, in the same style as its template's "What we know" or "Notes" section.

## 6. Show the draft and wait — unless the project says direct

Whether the user reviews drafts depends on the project. Read its project
profile with `wto profile` (exit 1 means there is none):

| Profile | Do |
|---|---|
| `Issue drafts: direct` (personal private projects) | File without waiting, then report what you filed (step 8). |
| `Issue drafts: review`, `Kind: work` or `Kind: public` | Show the draft and wait. |
| No profile, or anything unclear | Show the draft and wait. |

Even on a direct project, show the draft first when this conversation touched
anything private or the issue reaches beyond what the user asked for.

When reviewing, present before writing anything to the tracker; this covers
updates as well as new issues:

- Target: forge, `owner/repo`, tool
- New issue: title, labels, full body
- Update: the existing issue's number, title and link, then the comment
- For a split: the parent plus each child, in order, marking any piece that
  updates an existing issue instead

Write nothing until the user approves. Apply their edits and re-show if the
change is substantive. Their approval authorizes exactly what was shown. On a
direct project, filing authorizes exactly the issue you drafted; a split still
gets shown first.

## 7. Create or update

Write each body to a temp file outside the repo (the session's scratch
directory if it has one) and pass it by file — no shell-quoting of Markdown.

| Tool | Create |
|---|---|
| `gh` | `gh issue create -R owner/repo --title "<t>" --body-file <f> [--label a,b]` |
| `tea` | `tea issues create --login <name> --repo owner/repo --title "<t>" --description-file <f> [--labels a,b]` |
| `glab` | `glab issue create -R owner/repo --title "<t>" --description-file <f> [--label a,b] --yes` |
| `gitea` MCP | the issue write tool's create method, with owner, repo, title, body |

| Tool | Comment on an existing issue |
|---|---|
| `gh` | `gh issue comment <n> -R owner/repo --body-file <f>` |
| `tea` | `tea comments add <n> --login <name> --repo owner/repo -d "$(cat <f>)"` (no file flag) |
| `glab` | `glab issue note <n> -R owner/repo -m "$(cat <f>)"` |
| `gitea` MCP | the issue write tool's comment method |

Reopening a closed issue is a separate action — do it only if the user chose
"reopen" in step 4.

For a split: create the parent first, then each child with `Part of #<parent>`
in its body, then update the parent's checklist to link the children
(`- [ ] #12 …`). On GitHub, `gh issue create --blocked-by` can record
dependencies between children.

Check each CLI's `--help` if a flag is rejected; versions drift.

## 8. Report

Give the user each issue's number and URL, saying which were created and
which were updated. If anything failed partway through a
split, say exactly which issues exist and which don't. Then return to whatever
the conversation was doing before — filing the issue is a side trip, not a
change of task.
