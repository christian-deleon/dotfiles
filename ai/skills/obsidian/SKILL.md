---
name: obsidian
description: Write and organize notes in the user's Obsidian vault at `/home/cdeleon/Documents/Obsidian Main`. Use ONLY when the user explicitly mentions Obsidian, their vault, an MOC, or notes in that path — do NOT activate for general note-taking or markdown outside that vault. Covers atomic notes, fleeting vs permanent, MOCs, wikilinks.
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

## Vault structure

Read `README.md` in the vault before filing a note. The top-level folders are `Journal/`, `Projects/`, `Career/`, `Tech/`, `Business/`, `Family/`, `Health/`, `Home/`, `Finances/`, `Hobbies/`, `Wisdom/`, and `Attachments/`.

A folder earns a place when that subject already has about four notes. A single note sits in the parent folder. Do not make a directory for one note.

- **Discover existing structure first** — list the vault before creating a folder
- **Match an existing folder** — a Linux note goes in `Tech/Linux/` because that folder exists. A note whose subject has no folder sits in the parent (`Tech/Some AWS Note.md`)
- **Create a subfolder only past the size line** — about four notes on one subject, then `mkdir -p`

**WRONG:**
```
Write(filePath=".../Tech/AWS/AWS SSM SSH Proxy.md")  # one note does not get a folder
```
**CORRECT:**
```
Write(filePath=".../Tech/AWS SSM SSH Proxy.md")
Write(filePath=".../Tech/Linux/Install Python on Linux.md")  # Linux/ already exists
```

## Workflow

**Creating a note:**
1. Glob/Grep — check if a note on this topic already exists; if so, Edit instead of creating a duplicate
2. Grep frontmatter across the vault — discover existing tags before assigning any (e.g. search `^  - computer-science` in `**/*.md`)
3. List the vault — confirm the target folder exists. Create a subfolder only when that subject already has about four notes
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

## Directory boundaries

File by subject. `Projects/` is for work being built. Reusable reference goes in the subject folder (`Tech/`, `Business/`, and the others), written so a later project can use it. The note does not need to point back at the project. A project links to it with `[[wikilinks]]`.

**The test:** "Would this note be useful outside this project?" If yes, put it in the subject folder. If no, put it in that project.

## Key Rules

- One idea per note (atomic)
- `[[Wikilinks]]` on first mention of related concepts — this is Obsidian's core value
- Filenames must be globally unique; always include context (`"Real Estate Investment Questions.md"` not `"Questions.md"`)
- Tags: 2–4 per note, lowercase-hyphenated, reuse existing vault tags, frontmatter only (no inline `#hashtags`)
- **Search existing tags before assigning any** — grep the vault for tags already in use and reuse them; only introduce a new tag if no existing one fits
- **Tags must match content** — every tag must be directly supported by the note's actual content; do not add aspirational or loosely related tags
- Dated notes go in `Journal/` (`YYYY-MM-DD.md`). A note you cannot place also waits in `Journal/`
- A single note sits in its subject folder. Add a subfolder only when that subject has about four notes
- If unsure where a note belongs, ask the user
