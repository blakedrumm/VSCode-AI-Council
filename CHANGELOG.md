# Changelog

All notable changes to this project are documented here.

The version in `$ScriptVersion` is what the built-in update check compares, so it is the value that
decides whether users are told an update exists.

## 5.5.0

First public release.

### Added

- **Update checking.** On startup the installer compares its version against the published one and
  prints a link when a newer version exists. It reads a version string only, and never downloads or
  executes remote code. `-SkipUpdateCheck` disables it.
- **Recommended model set.** The picker marks a suggested roster detected from the live VS Code model
  catalog, taking the newest `powerful` or `versatile` model from each vendor. `[R]` selects it.
- **Previous configuration reuse.** Re-running the installer reads the models and coordinator model
  back out of the installed coordinator agent and offers to reuse them.
- **Interruption and resume protocol.** The coordinator classifies a mid-run user interjection as a
  redirect, a refinement, or a detour, tracks the run as a todo list, and resumes outstanding work
  instead of silently dropping it.
- Lens assignment is now shown next to each model before you confirm a selection.

### Changed

- Model size is read from the `category` field VS Code publishes for each model rather than inferred
  from the model name. Names that carry no size hint were previously misclassified.
- Version numbers are only compared inside a single vendor. Comparing them across vendors was
  meaningless, since the numbering schemes are unrelated.
- Unknown vendors are grouped by the leading token of the model name, so the one-model-per-vendor
  rule keeps holding for models this script has never seen.

## Earlier versions

Versions before 5.5.0 were not published.
