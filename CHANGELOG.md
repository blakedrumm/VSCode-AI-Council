# Changelog

All notable changes to this project are documented here.

The version in `$ScriptVersion` is what the built-in update check compares, so it is the value that
decides whether users are told an update exists.

## 5.7.9

### Added

- An ASCII banner reading VSCODE AI COUNCIL is printed at the top of an install run, so it is
  obvious at a glance which script is running and when its output starts.

## 5.7.8

5.7.7 taught the council to tell proof from belief. This release fixes the remaining findings from
the same review, which were all about work the council wasted or coverage it lost without noticing.
Again, nothing about the installer changes.

### Changed

- **A branch that never reports no longer disappears quietly.** An expert can fail outright, hit a
  rate limit, or come back with nothing usable, and the coordinator had no instruction covering it.
  The lens simply vanished while the final answer still looked complete, which makes it the failure
  a reader is least able to notice. The coordinator now names the dead branch and the uncovered
  lens, then re-dispatches it once, reassigns its scope, or records the gap as unresolved. Agreement
  among the survivors never stands in for the lens that never reported.
- **Cheap evidence is spent before model calls are.** The coordinator now spends the one or two tool
  calls that could collapse a question outright before it dispatches anyone, because one command
  that settles the matter beats five experts arguing about what it would have said. Related: a
  result already in hand can now cancel a branch that has not been dispatched yet.
- **Parallel branches stop rediscovering the same facts.** Experts cannot see each other, so
  anything missing from the brief is paid for once per branch. Five experts each spending three
  calls to find the same build command was the most common waste in a fan-out, so the shared facts
  now go in every brief even when they feel too obvious to write down.
- **Experts no longer guess about agents they cannot see.** The report field asking which expert
  they disagreed with required inventing the other branches' positions, since parallel experts have
  no view of each other. It now names a claim from their own brief, or an assumption a reader would
  otherwise hold.
- **The Tier 5 review aims at what the expert could not check.** Pointing the single review each
  branch gets at a claim the expert had already proven wasted it.
- **Tier 4 and Tier 5 dispatch the same roster**, and the coordinator now says so, so choosing
  between them is understood as a choice about depth rather than about how many models to use.
- **A new test is broken before it is trusted.** After adding a test, the coordinator now breaks
  what it covers, watches it fail, and puts the code back. A passing test proves nothing until it
  has been seen to fail for the right reason. This rule exists because a single mutation run found
  seven coverage holes in this repository that five experts reading the same tests predicted none
  of, which is the clearest evidence in the whole review that more readers are not the answer.
- The three additions that grew the always-on coordinator prompt were partly paid for by removing
  statements it already made elsewhere.

The suite is now 99 tests. The assertions added here were themselves mutation tested: each of the
ten new rules was broken in turn and every break was caught.

## 5.7.7

This release changes what the council is instructed to think, not what the installer does. Every
change comes from watching the council review its own repository roughly nineteen times and writing
down where it was wrong.

### Changed

- **An uncontested claim is now checked.** All the machinery for weighing evidence lived under a
  heading about resolving disagreement, so it only ran when two experts collided. A single confident
  expert reached the user with nothing in between, which is exactly how the worst error of the
  review got through. Claims are now classified as empirical, textual, or interpretive, and an
  empirical claim stays provisional until the coordinator runs it, whether or not anyone disputed
  it. An empirical tie is never broken by preferring the better-argued expert.
- **Experts now separate what they proved from what they believe.** The report opens with a line
  naming what the agent could actually do, and splits its findings into verified and unverified,
  each unverified claim carrying the exact check that would settle it. Every expert in the review
  turned out to have no way to run a command, while being told to rank reproducible tests and
  runtime behavior above documentation. They can no longer present reading as observation, and a
  precise falsification plan now counts for more than another paragraph of argument.
- **Experts stop at disconfirmation rather than at plausibility.** The old instruction was "stop
  searching once you can act", which rewards the first answer that looks right.
- **Experts must read what surrounds code they propose changing.** The most confidently wrong
  recommendation of the entire review was refuted by a comment three lines above the line it cited.
  That error needed no terminal to avoid, only twenty lines of reading instead of one.
- **Reviewers look at the artifact instead of only the summary they were handed.** A reviewer was
  given the expert's own account of its work, which is the version most favourable to its
  conclusion, and had no instruction to go and check.
- **Agreement is no longer treated as corroboration.** Experts reading the same file share one
  blind spot, so convergence says they agree, not that they are right.
- The coordinator prompt is shorter despite gaining all of this, because a duplicated synthesis
  section and several rules that restated each other were removed. It is read on every turn,
  including turns that use no experts at all, so its length is the most frequently paid cost in
  the system.

## 5.7.6

The security findings that 5.7.5 deliberately deferred, plus another Tier 5 review. The release
pipeline is the largest change: it no longer builds and publishes in one place.

### Changed

- **Building and publishing no longer share a job or a credential.** The release workflow ran the
  installer, the analyzer, and two test suites in the same job that later received the token used to
  publish, so anything executing during the build could have reached it. Building and testing now
  happen with read-only permissions and no secrets, and publishing happens in a separate job that
  never checks out or executes repository code. It downloads the candidate, then re-derives what it
  needs from the immutable commit through the API: it re-reads the installer at that commit and
  refuses to publish anything whose content does not match, confirms the committed file reports the
  version being published, refuses a tag that already points somewhere else, re-checks that the
  commit is contained in the repository's default branch, and validates the manifest and both
  hashes. SFTP publishing is a third job that holds only its own secrets.
- **A published version is now immutable.** Re-running a release used to replace the assets in
  place, which can leave a downloader holding a digest that no longer describes what is served.
  Publishing over an existing release now fails and asks for a version bump instead.
- **SFTP uploads are staged and renamed** rather than written straight to the live names, so an
  interrupted transfer cannot leave a published file truncated or the pair half updated.

### Fixed

- **Matching a file name is no longer treated as owning the file.** The sweep that removes agents
  from a previous configuration selected purely on the name, so a hand-written file called
  `mm-expert-something.agent.md` would have been deleted. A file is now only removed if its front
  matter is the kind this installer emits. Only the front matter is inspected, because the body of
  an agent file may legitimately quote front-matter syntax as an example. A file that fails the
  check is reported and never enters the managed set at all, so a rollback cannot write to it
  either.
- **Rollback could overwrite an edit made after the installer wrote the file.** Restoring now
  happens only while the file still holds exactly what this run put there, matching the rule the
  settings file already followed. A file that was changed, or deleted, after this run wrote it is
  left as it is and reported.
- **Removing a leftover file can no longer fail an install that already succeeded.** A file that
  vanished between the check and the delete threw, which rolled back a roster that was written and
  validated.
- **U+FFFE and U+FFFF were accepted in model names.** Both are noncharacters that YAML excludes,
  so they could produce front matter VS Code cannot read.

### Notes

- Copying the VS Code state database to the per-user temp directory is deliberate and documented in
  place. The copy is randomly named and removed in a `finally`; a process killed mid-read can leave
  one behind, and it contains VS Code state the same user can already read.

## 5.7.5

Three full council reviews of 5.7.4. Every fix below was reproduced first, and the test suite was
then mutation-tested: sixteen deliberate defects were injected into a copy of the installer to find
out which ones the suite failed to notice. Five slipped through, and the tests that should have
caught them were rewritten.

### Fixed

- **A workspace could still choose which models the council runs.** 5.7.4 restricted the front
  matter parser but left the prose fallback scanning the whole coordinator file, so a single line in
  the prompt body still set the roster. Every coordinator this installer writes declares its roster
  in front matter, so the fallback was removed rather than narrowed.
- **A real settings.json could not be edited at all.** VS Code accepts keys that differ only by
  case, and `terminal.integrated.env.windows` holding both `Path` and `PATH` is an ordinary thing to
  have. PowerShell refuses to build an object from that, so the installer called a valid file
  invalid and wrote nothing. It now falls back to a dictionary that can represent those keys.
- **That fallback would not have fired outside English.** It keyed off the text of the error
  message, which PowerShell translates, so a German or Japanese host would have hit the original
  failure. The fallback is now structural, and a genuinely malformed file still surfaces the first
  parser's message rather than the fallback's.
- **The Windows PowerShell fallback was stricter than the parser it replaced**, refusing settings
  files above 2 MB or nested deeper than 100 levels. Both limits are now raised explicitly.
- **A cleanup failure could hide the error it was reporting.** Releasing the installer mutex throws
  if ownership was lost, and that throw replaced the real failure on its way out. Each cleanup step
  is now isolated.
- **The coordinator picker could not be escaped.** It looped forever on any input that was neither
  empty nor a listed number, which a host whose prompt never blocks will produce indefinitely. It
  now gives up after 25 attempts, like the model picker.
- **A path containing the word "insiders" broke VS Code detection.** The flavor test matched the
  whole install path, so a stable install under such a path looked for the Insiders CLI and reported
  none. It now tests the install folder name.
- **A file passed as the workspace was accepted**, producing a nonsensical agent directory and a
  confusing later failure. It must now be an existing directory.

### Changed

- **The council no longer contradicts itself about Tier 5 review.** The coordinator required every
  nested-review directive to name a concrete target, then issued a procedural instruction instead of
  one. Tier 5 dispatches before any analysis exists, so it now names the class of claim to challenge
  and says why that tier is the exception. The expert prompt now declares that same carve-out, so an
  expert reading its own schema literally can no longer treat a required Tier 5 review as malformed
  and skip it. Only the coordinator saw the explanation before.
- **A Tier 5 brief told experts to leave the lens it had just assigned them.** The override appended
  to every brief asked for cross-domain findings, while the expert prompt forbids expanding into
  another expert's lens, and the coordinator's own reminder that the lens still applies was never
  sent. The lens constraint now lives inside the verbatim override, which is the only part the
  expert receives.
- **Reviewers were free to ignore the question they were asked.** A reviewer told to attack the
  weakest point could substitute its own target for the one the expert supplied, which is the whole
  value of a targeted review. It now attacks the supplied target first, then reports anything weaker.
- **A linked agent directory no longer has files deleted through it.** A junction or symlink
  anywhere in the agent path silently redirects every write, and an experiment confirmed the stale
  sweep was deleting matching files in the link target rather than in the directory the user named.
  Writing through a deliberate link still works, because sharing agents between workspaces is a
  reasonable thing to set up, but the destructive half now stops and says so.
- The readme documents what a single-model install actually does, rather than describing
  cross-model review as though it always applies.
- The suite is 73 tests on PowerShell 7 and Windows PowerShell 5.1, up from 53. New coverage
  includes the settings-path resolver, the coordinator picker, the update check, expert tool
  permissions, deletion through a linked directory, a guard that the `-Models` limit still matches
  the number of review lenses, and the settings rollback itself, which is now exercised by making
  activation fail after the setting was written.
  cross-file check that the Tier 5 brief the coordinator emits is one the expert accepts.

## 5.7.4

Closes the findings the 5.7.2 council review left open, plus one defect found while fixing them.
Every change is covered by a test that fails without it.

### Fixed

- **The evidence ranking the agents use had already drifted.** The same eight-item list was written
  out by hand in two prompts and had diverged at item 6, and the expert prompt carried a third,
  prose restatement of the same ranking. Experts, reviewers, and the coordinator now render one
  shared constant, so the list the council uses to settle disagreements can no longer disagree with
  itself.
- **A roster could be declared from the prompt body.** Recovering a previous installation scanned
  every line of the coordinator file for `model:` and `agents:`, so those keys anywhere in the
  workspace-controlled prompt body were read as if they were front matter. Only the leading
  delimited block is parsed now, and a block with no closing delimiter is treated as no front matter
  rather than as a block that runs to the end of the file.
- **A failed atomic replace was confirmed by decoded text.** When `File.Replace` reported an error,
  the recovery path compared the file as text, and a byte order mark or an invalid sequence can
  decode equal to the intended text. It now compares raw bytes, using the same comparison the
  unchanged-file check already uses.
- **An unparseable settings file was reported as a clean success.** When the setting was already
  true the installer returned before validating the file, so a settings.json VS Code cannot parse
  looked fine even though VS Code would ignore it and leave nested subagents inactive. That case now
  warns. Nothing is written, so it is a warning rather than a failure.

### Changed

- **Release and validation dependencies are pinned.** Both workflows installed PSScriptAnalyzer and
  Pester from the gallery with a floating version, and the release job runs them alongside the
  credentials it later publishes with. Exact versions are now required, and the validation workflow
  pins the checkout action by commit rather than by moving tag.
- **A release cannot publish a version the installer contradicts.** Overriding the version through
  the workflow input only warned, so a mismatched tag could ship an installer whose update check
  would tell every user an update existed forever. The release now fails instead.
- Static analysis covers `.github/scripts` and `tests` in both workflows, not just the installer.
  The release-notes generator had never been analyzed, which is how a call that fails on both
  PowerShell editions reached it. Analyzer and parser annotations now name the file they came from
  instead of always blaming the installer.
- The readme version badge is checked against the version constant, and the release workflow's
  version input is described as the confirmation it now is rather than an override.

## 5.7.3

Every item below was found by a full council review of 5.7.2 and reproduced with a failing test
before it was fixed. Four of them were introduced by 5.7.0 or 5.7.2.

### Fixed

- **Rollback could destroy a settings file the installer never wrote.** 5.7.2 set its rollback flag
  before calling the settings editor, so the flag meant "reached this step" rather than "changed
  this file". Any later activation failure then restored a stale snapshot over settings the
  installer had not touched, and the guard that refuses to write when the file changed underneath it
  threw straight into that restore, turning a safety check into the data loss it existed to prevent.
  The editor now records the write itself, and rollback restores only while the file still holds
  exactly the bytes this run wrote. Proven by fault injection, with a negative control confirming a
  genuine write is still rolled back.
- **An empty settings.json permanently blocked the setting.** An empty or whitespace-only file is
  parsed as `{}`, but the pre-write concurrency check compared the real file against that
  substitute, so it always reported that VS Code had changed the file and refused to write. The
  check now compares the file against its own original text.
- **Windows PowerShell reported Copilot as missing when it was installed.** Reading
  `extensions.json` repeated the top-level JSON array bug fixed elsewhere in 5.7.1: Windows
  PowerShell collapses the array into a single element inside `@()`, so every extension id merged
  into one unmatchable string.
- **Cache read errors were reported as an empty cache.** A failed SQLite prepare or step, or a
  malformed value, returned success with no records, so the retry added in 5.7.2 never fired for the
  torn-snapshot case it was built for and the installer fell back to the built-in catalog instead.
- **Backup retention kept eleven directories, not ten.** The current run's folder was excluded from
  the sort before the cap was applied, so it was never charged against the documented limit.

### Changed

- **A single-model install no longer contradicts itself.** Tiers 2 and 4 require a second model, yet
  a one-model roster still advertised them, priced its Tier 3 fallback as including nested reviews
  it explicitly skips, disagreed with its own expert file about that policy, and emitted "up to 1
  parallel expert calls". Those tiers are now marked unavailable, the costs match the behavior, and
  the coordinator and expert state one policy. The root cause was that no test used a one-model
  roster, so the entire branch was unexecuted.
- **The coordinator now closes every answer with a TL;DR.** Long multi-expert responses were hard to
  act on at a glance, so the final response ends with a short plain-language summary of the outcome.
- Four `continue` statements in the JSON tokenizer were removed. Inside a `switch` they only leave
  the switch rather than the enclosing loop, so they read as flow control while doing nothing.
- The regression suite is now 39 tests on PowerShell 7 and Windows PowerShell 5.1, covering the
  single-model roster end to end, settings rollback state, empty settings files, retention limits,
  and a byte order mark added to an otherwise unchanged agent file.

## 5.7.2

### Fixed

- **A failed installation could leave the VS Code setting enabled.** The settings editor writes the
  file and then verifies it, but both verification failures threw before the function returned, so
  the flag the rollback guard depended on stayed false and the setting was never restored. The guard
  now keys on the snapshot captured before the write. A fault-injection run confirms the file is
  restored byte for byte, and a negative control confirms the previous guard was not.
- **Post-install validation never checked the generated tool list or the target.** `Test-AgentFile`
  counted front matter keys but only inspected `tools` for the leaf-agent negative case, so a
  tool-name regression could ship. Both values are now asserted for every role from one shared
  constant, which also removes any chance of the generator and the assertion drifting apart.

### Changed

- **Unchanged agent files are no longer rewritten.** A repeated install compares raw bytes and skips
  files that already match, so a no-op re-run creates no backups and leaves timestamps alone. The
  comparison is byte-level on purpose, because a decoded string hides a byte order mark that must
  never reach the front matter.
- **The preflight no longer writes to a temporary directory.** It validates the exact content the
  live write will produce in memory, removing a full write and read of every generated file while
  keeping the guarantee that a template regression cannot touch the installed roster.
- **The model-cache retry only fires on a genuine read failure.** Cached-model reads now return an
  explicit result object, so a snapshot that read cleanly and simply held no agent-capable model no
  longer triggers a second database copy or the misleading "unreadable" message.
- **The roster is recovered from the coordinator's front matter.** Reuse previously depended on a
  regex over one generated prose sentence, so rewording that sentence silently reset a
  noninteractive re-run to the built-in defaults. The prose parser is retained as a fallback.
- Backup folders beyond the newest ten are pruned after a successful install, and backing up a file
  now logs one line instead of two.
- `$MaxModelCount` is derived from the lens catalog instead of being repeated as a literal.
- `-Models` now reports that the supplied names were never checked against the VS Code catalog.
- Removed an unreachable single-model reviewer fallback and the stale comment justifying it.
- The regression suite is now 27 tests on PowerShell 7 and Windows PowerShell 5.1.

## 5.7.1

### Changed

- **Dot-sourced cache discovery now has a versioned native wrapper.** A long-lived PowerShell
  session can retain an `Add-Type` definition after the script that created it changes. The model
  cache reader now uses the versioned `VSCodeCouncil.SqliteCacheV1` type, so an older same-namespace
  wrapper cannot be mistaken for the current native contract.
- **Transient model-cache snapshots are retried once.** If the first copied SQLite snapshot is empty
  or incoherent while VS Code is writing it, the installer takes one fresh snapshot before falling
  back to the built-in catalog.
- The regression suite now has 23 tests, including cross-edition model-array normalization,
  stale-wrapper isolation, and one-shot snapshot recovery on both PowerShell 7 and Windows
  PowerShell 5.1.
- Manual release runs no longer request SFTP upload by default. It remains available as an explicit
  workflow option when the required repository secrets are configured.

### Fixed

- **Windows PowerShell 5.1 model discovery always fell back to the built-in catalog.** In 5.1,
  calling `ConvertFrom-Json` directly inside `@()` preserves a top-level JSON array as one nested
  `System.Object[]`. The cache filter therefore saw no `identifier` property and discarded every
  model. The parser now assigns the JSON result first and normalizes it in a second step, yielding
  the same record sequence on PowerShell 5.1 and PowerShell 7.

## 5.7.0

### Added

- **Required Tier 5 peer review.** Every Tier 5 expert now forms its own position, then invokes one
  configured leaf reviewer to attack the strongest material assumption before finalizing. A
  five-model Tier 5 run therefore has up to five expert calls and five reviewer calls.
- **Explicit nested-review directives.** Every expert brief now carries `REQUIRED`, `AUTHORIZED`, or
  `SKIP`, plus a named reviewer and target where applicable. Tier 3 and Tier 5 require review, Tier 4
  can authorize it per qualifying branch, and Tiers 1 and 2 skip it.
- **Transactional activation.** The complete generated roster is preflighted before live agent files
  are touched. The installer snapshots files it owns and the original VS Code setting, then restores both
  when activation fails before validation completes.
- **Behavioral regression suite.** Twenty Pester checks now cover generated invocation flags, Tier 5
  policy, model-name boundaries, root-aware JSONC mutation, strict UTF-8 handling, and a real
  multi-model workspace install. CI and release validation run them on PowerShell 7 and Windows
  PowerShell 5.1.

### Changed

- Hidden experts and reviewers now use `user-invocable: false` with
  `disable-model-invocation: false`, while the visible coordinator remains protected from subagent
  invocation. Post-install validation asserts both values for every role.
- Stale agents are removed only after the replacement roster passes validation. A process-wide mutex
  rejects overlapping installer runs.
- Agent and settings reads now use strict UTF-8 decoding on both PowerShell editions. Invalid bytes
  fail before backup or mutation instead of being silently replaced.
- The settings editor now locates only root properties, rejects duplicate root keys, leaves nested
  lookalikes untouched, avoids no-op rewrites, and detects concurrent changes before committing.
- The update check now reads only GitHub release metadata. The raw-script fallback was removed, so the
  check no longer downloads the published installer body and has one bounded network attempt.
- VS Code detection no longer executes a `code` command inherited from `PATH`. The optional opener is
  resolved beneath a verified standard installation and failures are reported as warnings after a
  successful install.
- Generated coordinators use the canonical `todo` tool name. VS Code's legacy `todos` alias remains
  compatible with older generated files.

### Fixed

- **Workers could be excluded from subagent invocation.** The front-matter builder previously emitted
  `disable-model-invocation: true` for every role, contradicting VS Code's documented subagent flag and
  the council's explicit allowlists.
- Uppercase `C` in the model picker now opens custom-model entry as advertised.
- Malformed JSON in the current VS Code model-cache key now falls through to the legacy key, and each
  prepared SQLite statement is finalized independently.
- Duplicate catalog entries no longer produce duplicate recommendations, and oversized numeric model
  versions fail closed instead of overflowing.
- Model names are now length-bounded and reject leading or trailing whitespace, Unicode format
  controls, and malformed surrogate code points.
- Atomic replacement failure no longer falls back to truncating a live target. The installer preserves
  the old file or retains an explicit recovery copy when filesystem state is uncertain.

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
