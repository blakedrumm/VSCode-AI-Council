# Changelog

All notable changes to this project are documented here.

The version in `$ScriptVersion` is what the built-in update check compares, so it is the value that
decides whether users are told an update exists.

## 5.6.1

No change to the installer's behavior. This is the first release published by the release workflow
rather than by hand.

### Changed

- **Releases are now built and published by `.github/workflows/release.yml`.** It reads
  `$ScriptVersion`, refuses to continue when the `.NOTES` help block disagrees with it, runs the
  parser, PSScriptAnalyzer, and a real non-interactive install that exercises `Test-AgentFile`,
  then publishes the release. The release commit must be reachable from `main`, and the assets are
  extracted from that commit with `git archive` rather than copied from the working tree.
- **`Install-VSCodeCopilotCouncil-v5.txt` is now published alongside the `.ps1`**, as a
  byte-identical copy for downloaders whose mail gateway or proxy blocks a `.ps1`. It is generated
  during the release rather than committed, so the two cannot drift, and the release notes publish
  both SHA-256 digests so the match can be verified.

## 5.6.0

### Added

- **Tier 5, unconstrained brainstorming.** A sixth coordinator tier that dispatches the full parallel
  team and appends an explicit override to every delegation brief, lifting the expert eight-line limit
  so each one returns an exhaustive report. It triggers only on an explicit keyword such as brainstorm,
  deep review, or unconstrained, and the coordinator is forbidden from selecting it on its own
  initiative.
- **Expert progress narration.** Experts now state what they are checking before each significant
  search or tool call, and carry that trace into their report as a CHECKED line, since only their final
  message reaches the coordinator.
- **Visible synthesis reasoning.** The coordinator now shows how it weighs opposing expert findings and
  names the artifact that resolved each contradiction, rather than presenting a verdict whose
  derivation cannot be followed.

### Fixed

- **Unicode line terminator bypass in model name validation.** `Test-ModelName` rejected the ASCII
  control range but accepted U+0085, U+2028, and U+2029. Those terminate a line for a YAML parser but
  not for the .NET multiline anchor that post-install validation counts front matter keys with, so a
  crafted model name could have introduced a second front matter key the validator never saw. All three
  are now rejected. No real model name is affected.

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
