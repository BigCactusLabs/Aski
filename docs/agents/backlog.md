# Backlog conventions

Aski develops in the open: the task queue lives in-repo under `backlog/`, managed by the [Backlog.md CLI](https://github.com/MrLesk/Backlog.md) (`backlog` ≥ 1.47). Tasks use the `ASKI-NN` id prefix. (`ASTSK-NN` ids in `CHANGELOG.md` and `docs/Research/` refer to the pre-public private tracker; the two sequences are unrelated.)

## Hard rules

- **Never edit files under `backlog/tasks/` directly.** Create and modify tasks only through the CLI (`backlog task create`, `backlog task edit`). Direct file edits break the CLI's bookkeeping.
- **Never pass section markers inside CLI text.** Text given to `-d`, `--notes`, or `--append-notes` must not contain `<!-- SECTION:*:BEGIN/END -->` or `<!-- AC:BEGIN/END -->` lines. The CLI wraps the text in a fresh marker pair without stripping the ones inside, so pasting a description back from the task file or `--plain` output nests markers and later edits swallow the AC and Notes sections (ASKI-60, 2026-09-01; upstream MrLesk/Backlog.md#990). If a task file shows more than one `SECTION:DESCRIPTION:BEGIN`, stop and report it.
- **Text only.** No binaries, images, or attachments in backlog content — SwiftPM consumers clone the whole repository, so the queue stays small and diff-able.
- **Append notes; do not replace them.** Use `--append-notes` to add a note. `--notes` replaces every existing note, and once erased a task's record (ASKI-54).
- **Status and acceptance criteria describe production.** Record a rejected or unmerged experiment in the task notes and its evidence folder. Do not check an acceptance criterion for a candidate that was not integrated, and return the task to To Do when its arm is rejected unless someone is working on the next arm. ASKI-2 and ASKI-4 broke this and were corrected on 2026-11-24.

## Querying

```bash
backlog task list --plain --status "To Do"        # the live queue
backlog task list --plain --status "In Progress"
backlog task view ASKI-1 --plain
```

`--plain` produces stable, pipe-friendly output; prefer it in scripts and agent workflows.

## Creating and editing

```bash
backlog task create "Title" -d "Description" --ac "First acceptance criterion"
backlog task edit ASKI-1 --status "In Progress"
backlog task edit ASKI-1 --append-notes "Progress note"
```

Rely on `--help` per subcommand for the full field surface; run `backlog instructions overview` once per session for the CLI's own agent guidance.

## Repo-specific configuration

`backlog.config.yml` keeps `remote_operations: false` and `check_active_branches: false` — the queue's truth is the checked-in state on the current branch, and the CLI must not scan other branches or contact remotes. Task work merges via PRs into `main` like any other change.

Because the CLI numbers a new task from the tasks on the current branch only, filing a task while an open PR adds one gives a second task with the same id (ASKI-104 and ASKI-105 hit this). Before `backlog task create`, list the task files added by open PR branches (`git diff --name-only --diff-filter=A origin/main...origin/<branch> -- backlog/tasks`) and make sure the CLI sees the highest id.
