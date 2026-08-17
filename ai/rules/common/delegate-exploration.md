# Scout only for complex exploration

Scout exists to keep bulky search residue out of the parent context and
save tokens. The child's search dumps die with that child; the parent
keeps only the short report. A wide hunt run inline persists for the
rest of the session and is re-sent on every later call.

Default to searching and reading inline. Spawn `scout` only when that
hunt would leave a large dump in the parent:

- **Complex request:** you do not know where to look, and answering needs
  a wide hunt (find-all-usages, naming sweeps, multi-subsystem traces) or
  reading a very large log/dump you cannot target by line range.
- **Complex project:** a large or unfamiliar codebase where that hunt
  would pull a lot of search output into the parent.

Do **not** spawn scout when the work is small enough that a child costs
more tokens than it saves:

- Simple tasks (one symbol, one config, one known directory, a handful of
  files).
- Small or familiar projects (dotfiles, a single package, a repo whose
  layout you already know).
- Cases where the file or a short list of likely paths is already known.
- A few greps or reads you can run yourself — including several at once.

Keep the conclusion, not the file dumps. Once delegated, wait for the
scout's answer — never re-run the same search inline.

The scout finds and locates; it does not decide. Treat its `file:line` +
excerpt as evidence to reason over yourself, not as a conclusion to adopt
untouched — read the excerpt, not just the claim built on top of it. If a
finding is surprising, negative ("X doesn't exist/isn't handled anywhere"),
or will drive an irreversible action, open the cited location yourself before
acting on it. A scout's summary can miss or misstate what it found;
verifying the load-bearing ones is cheap insurance, not wasted delegation.
