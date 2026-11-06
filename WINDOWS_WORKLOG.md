# Windows port work log

Newest first. What was done, the evidence, decisions and why, what is next.

## 2026-11-06: Reorganized around the Mac being available

**Starting point.** A C# port from a prose spec, 1,050 passing self-checks, no Mac comparison ever run, and all of it
untracked in git on the laptop.

**Done**
- Committed the whole port to a new `windows` branch and pushed it to GitHub (`e30fec9`, `9dff43a`). Mac build products
  no longer tracked on this branch. The imported conversation log and signing keys are excluded because the repo is public.
- Set up the Mac dev clone at `~/Documents/Visual Studios/Projects/spider-buddy-windows`, and git sync with the laptop.
- Wrote `lap` and the bridge. SSH is session 0 with no desktop, so GUI runs go through a one-shot interactive scheduled task
  under a headless conhost. Verified with real screenshots.
- Baseline: Release build 15 s, `tools all` 1050/1050 in 8 s.
- Wrote the workflow doc, status table and this log. Moved older docs to `docs/windows/`.

**Decisions**
- Oracle is v1.0.1 (`Sources` tree `7c878d73`). Leg system v2 comes later. (Owner.)
- Branch in the same repo, pushed. (Owner.)
- Laptop is available for development; the owner sometimes needs it for class. Back off when in use. (Owner.)
- Oracle runs of the real Mac app use a separate bundle id, because `capture-app.sh` rewrites the settings that hold the
  owner's real spider.

**Next:** see the status file.
