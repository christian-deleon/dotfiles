---
name: obsidian
description: Write and organize notes in the user's Obsidian vault following best practices: atomic notes, fleeting vs permanent notes, splitting large docs, MOCs, and wikilinks. Only activate when the user explicitly mentions Obsidian or their vault.
compatibility: opencode
---

## Vault

- Disk path: `/home/cdeleon/Documents/Obsidian Main`

Use standard file tools for all vault operations:
- **Read** — read existing note content
- **Write** — create or overwrite a note
- **Edit** — make targeted changes to an existing note
- **Glob** — find files by name pattern (e.g. `**/*.md`)
- **Grep** — search note content (e.g. find tags, wikilinks, topics)
- **Bash `mkdir -p`** — create subdirectories

## Vault Structure (PARA)

- `Projects/` — active work with a defined end
- `Areas/` — ongoing responsibilities (career, health, finance, etc.)
- `Resources/` — reference/knowledge material
- `Journal/` — dated notes only (`YYYY-MM-DD.md`)
- `Attachments/` — binary files only

**Always use topic-specific subdirectories.** Never place notes directly in a top-level PARA folder. Every note must go into the most specific subdirectory that matches its topic. (`Journal/` is exempt — dated notes go directly there.)

- **Discover existing structure first** — use Glob (`**/*.md`) or Bash `ls` to see what subdirectories already exist before creating new ones
- **Match existing structure** — if `Resources/Computer Science/` already exists, a note about Python goes there, not in `Resources/` directly
- **Create subdirectories when warranted** — if no matching subdirectory exists for a clearly distinct topic, use `mkdir -p` to create one
- **Be specific** — `Resources/LLM/` not `Resources/`; `Projects/MyApp/` not `Projects/`; `Areas/Career/` not `Areas/`

**WRONG:**
```
Write(filePath=".../Resources/Python Decorators.md")
```
**CORRECT:**
```
Write(filePath=".../Resources/Computer Science/Python Decorators.md")
```

## Workflow

**Creating a note:**
1. Glob/Grep — check if a note on this topic already exists; if so, Edit instead of creating a duplicate
2. Grep frontmatter across the vault — discover existing tags before assigning any (e.g. search `^  - computer-science` in `**/*.md`)
3. Glob or Bash `ls` — confirm the target subdirectory exists; `mkdir -p` if not
4. Write — create the note with frontmatter, content, and wikilinks
5. Edit related notes and MOCs to add `[[wikilinks]]` back to the new note

**Updating a note:**
1. Read — always read current content first
2. Edit — make targeted changes; prefer appending over replacing entire content

## Note Structure

```markdown
---
tags:
  - category/subcategory
created: YYYY-MM-DD
---

One or two sentences summarizing the core idea.

## [Main Section]

Content. Link to related concepts using [[Wikilinks]] on first mention.

## Related Notes

- [[Related Note One]]
- [[Related Note Two]]
```

**No H1 heading in the note body.** Obsidian's "Inline Title" feature (Settings → Appearance → Show inline title) renders the filename as an H1 at the top of every note automatically. Adding `# Note Title` inside the file duplicates this and creates two sources of truth that can drift out of sync when files are renamed.

## Directory Boundaries

Each PARA directory has a distinct purpose. Do not mix them.

| Directory | Purpose | Examples |
|-----------|---------|---------|
| `Projects/` | Active work tied to a specific deliverable — decisions, competitive analysis, project-specific findings, implementation notes | Vendor comparison notes, system architecture decisions, integration notes |
| `Resources/` | Generalized reference knowledge reusable across any project — concepts, technologies, landscapes, methodologies | Technology landscape overviews, design patterns, algorithm theory |
| `Areas/` | Ongoing responsibilities with no end date | Career, health, finances |
| `Journal/` | Fleeting notes, brain dumps, dated entries | `2026-02-19.md` |

**Research always goes in `Resources/`, written as a standalone reference with no project-specific framing.** Any project that needs it links to it via `[[wikilinks]]`. The research note itself does not reference back to any project.

**The test:** "Would this note be useful outside the context of this project?" If yes → `Resources/`. If no → `Projects/`.

## Key Rules

- One idea per note (atomic)
- `[[Wikilinks]]` on first mention of related concepts — this is Obsidian's core value
- Filenames must be globally unique; always include context (`"Real Estate Investment Questions.md"` not `"Questions.md"`)
- Tags: 2–4 per note, lowercase-hyphenated, reuse existing vault tags, frontmatter only (no inline `#hashtags`)
- **Search existing tags before assigning any** — grep the vault for tags already in use and reuse them; only introduce a new tag if no existing one fits
- **Tags must match content** — every tag must be directly supported by the note's actual content; do not add aspirational or loosely related tags
- Fleeting/rough → `Journal/`; lasting reference → PARA directories
- **Never place notes directly in a top-level PARA folder** — always use a topic-specific subdirectory (e.g., `Resources/LLM/`, not `Resources/`). `Journal/` is exempt.
- If unsure where a note belongs, ask the user
