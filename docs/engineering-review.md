# Engineering Review

## Outcome and Scope

This Tier 5 review implemented reproduced correctness and data-preservation fixes in the installer,
model-reference scanner, generated agent contracts, regression suite, and CI configuration. It keeps
Windows PowerShell 5.1 compatibility, the existing public installer surface, the shipping version
5.18.0, and initially kept the checked-in recommendation reference. Changes are recorded as
Unreleased. The publication follow-up below records the subsequent pre-push reference refresh.

Five expert reports and two targeted leaf reviews informed the work. The coordinator inspected the
evidence, ran all commands, and made all edits. Agent names below identify configured agents, not
independently verified runtime model identities. An earlier interrupted dispatch had no retained
reports and contributed no evidence; the completed reports were not dispatched again.

The review itself did not commit, push, publish a release, or install into the user's live agent
directories. The designated maintainer's live recommendation update was deferred until publication.

## Ranked Findings and Implemented Changes

### High: User Files and Executable Content

| ID | Finding and outcome | Evidence and discriminating check |
| --- | --- | --- |
| F1 | A writer could complete its mutation and then throw before the outer loop recorded its output. Rollback missed the new file or failed to restore its previous bytes. `Install-AgentFile` now records intended bytes before attempting the write. | [Write tracking](../Install-VSCodeCopilotCouncil-v5.ps1#L4365); [post-write fault injection](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1881) failed for both new and pre-existing targets before the fix. |
| F2 | Rollback directly truncated live files. Restores now use the shared staged `Write-AtomicFile`; a blocked replacement fails without falling back to a destructive direct write. Failed attempts restore the prior attributes. | [Atomic writer](../Install-VSCodeCopilotCouncil-v5.ps1#L856), [snapshot restore](../Install-VSCodeCopilotCouncil-v5.ps1#L1062); [locked-target test](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L819) denies delete sharing while allowing reads and writes. |
| F3 | Post-write read-back could record another writer's bytes as this run's output. Settings comparison decoded away a concurrent BOM change. Both rollback paths now compare exact intended bytes and preserve detected competing content. | [Agent concurrency test](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1907), [settings re-encoding test](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1929); both exposed lost concurrent edits before repair. |
| F4 | Generic worker-shaped front matter was enough to authorize deletion. Ownership now requires a canonical, unambiguous header and agreement among the worker name, first model, generated description, and class tool set. | [Ownership predicate](../Install-VSCodeCopilotCouncil-v5.ps1#L4440), [uninstall tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L3326); generic lookalikes, duplicate keys, quoted duplicate keys, and incorrect tools were rejected after the repair. |
| F5 | Uninstall could delete a replacement written while it backed up an inspected candidate. It now compares the inspected bytes again after backup and reports a changed file as skipped. | [Removal engine](../Install-VSCodeCopilotCouncil-v5.ps1#L4597), [backup-time replacement test](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L3531); the test initially observed one deletion, then zero. This narrows, but does not eliminate, a compare/delete race. |
| F6 | Duplicate root policy keys silently selected a later value. Policy import now rejects exact, case-variant, and escaped duplicate names before deserialization, including unknown root keys. | [Policy import](../Install-VSCodeCopilotCouncil-v5.ps1#L1734), [policy tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L3100); exact and escaped duplicate cases failed to throw before the fix. |
| F7 | Alias selection could check one name against policy but emit another. Selection, policy entries, exclusions, and generated identities now use canonical names; converging aliases deduplicate before roster generation. | [Canonical policy check](../Install-VSCodeCopilotCouncil-v5.ps1#L1824), [public CLI alias tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1451); a blocked emitted model was previously installed. |
| F8 | Scanner alias application used whole-file replacements even when AST inspection identified a narrower literal. It changed comments and the alias registry, and a quoted replacement could add executable statements. Application now uses constant-literal extents, leaves the registry and command names alone, rejects unparsable PowerShell, and uses PowerShell's `EscapeSingleQuotedStringContent` encoder. | [Scanner application](../.github/scripts/Scan-ModelReferences.ps1#L421), [literal-safety tests](../tests/Scan-ModelReferences.Tests.ps1#L24); both ASCII and smart-quote payloads produced extra statements before their respective repairs. Tests parse these fixtures; they never execute the injected statement. |
| F9 | Scanner writes used host-default text encoding, dropped BOMs, and overwrote existing text backups. Reads are now strict UTF-8, backups are byte copies with unique successors, and changed files are staged and replaced atomically after content checks. | [UTF-8 snapshot reader](../.github/scripts/Scan-ModelReferences.ps1#L118), [byte and backup tests](../tests/Scan-ModelReferences.Tests.ps1#L57); BOM and previous-backup regressions failed before the fix. |
| F10 | Workspace integration tests still used the real user's backup root and could invoke normal retention there. Installer test variants now rewrite actual `$HOME` AST references into Pester's sandbox before execution. | [Sandbox helper](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L121); full installer integration tests pass under both supported hosts. A Windows PowerShell hashtable-sort difference was caught and fixed using an explicit offset expression. |

### Medium: Configuration, Contracts, and CI

| ID | Finding and outcome | Evidence and discriminating check |
| --- | --- | --- |
| F11 | Registry `Preferred` values did not select otherwise defaulted roles. They now replace unattended built-in defaults; explicit CLI selections, picker choices, and accepted reuse retain priority. | [Default selection](../Install-VSCodeCopilotCouncil-v5.ps1#L5639), [precedence tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1479); the registry-default case failed before repair. |
| F12 | Reusing a coordinator lost its fallback chain. Recovered fallback order is now preserved unless an explicit coordinator override replaces it. | [Coordinator resolution](../Install-VSCodeCopilotCouncil-v5.ps1#L5685), [reuse tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1510); the recovered chain was previously reduced to its primary. Expert chains are still rebuilt from the registry, not recovered from worker files. |
| F13 | Recommendation ties depended on culture and PowerShell edition. Numeric ranks from ordinal name and family order now supply deterministic tie-breaks without changing the reviewed reference set. | [Recommendation ranking](../Install-VSCodeCopilotCouncil-v5.ps1#L2622), [punctuation and culture tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L360); the two hosts disagreed on punctuation order before repair. |
| F14 | Reviewer briefs could lose the original task's scope and tool restrictions. Nested and coordinator-authored briefs now carry roots, permitted tools, hard constraints, compatibility, and non-goals. A reviewer missing authorized scope must report that gap rather than broaden discovery. | [Generated contract tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1030); these verify emitted instructions, not model obedience. |
| F15 | Malformed nested-review directives, unmatched explicit risks, and the exact capability schema were inconsistent. Prompts now fail closed on contradictory directives, assign explicit in-scope risks, and include `CAPABILITY` in the exact output block. | [Delegation contract tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1030); seven new contract cases initially failed across these and related prompt defects. |
| F16 | Stop requests phrased as questions were treated as detours, and a missing report was treated as proof a branch must run again. Prompts now honor intent, pause disputed actions, and check retained results or status before considering a repeat. Single-model Tier 3 sequencing and execution attribution were also corrected. | [Coordinator generation](../Install-VSCodeCopilotCouncil-v5.ps1#L4143), [contract assertions](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1030). |
| F17 | Configured names and absent explicit reviewer fallbacks were described as proof of model independence. A shared caveat now appears in all three roles and the console; coordinator rosters expose explicit expert fallbacks. | [Shared identity policy](../Install-VSCodeCopilotCouncil-v5.ps1#L555), [fallback disclosure](../Install-VSCodeCopilotCouncil-v5.ps1#L3881); tests verify all roles carry the caveat. Runtime routing remains unverified. |
| F18 | Module installation did not name its repository, and validation checkout retained credentials. Both workflows now select PSGallery explicitly for already-pinned modules; validation disables credential persistence. Release publishing job structure and permissions were retained. | [Validation workflow](../.github/workflows/validate.yml#L16), [release module install](../.github/workflows/release.yml#L182), [workflow tests](../tests/ReleaseWorkflow.Tests.ps1#L61); the two new hardening checks failed before the YAML changes. |
| F19 | Unchanged snapshot rollback rewrote identical bytes and timestamps. Byte/attribute equality now avoids redundant replacement. | [Snapshot restoration](../Install-VSCodeCopilotCouncil-v5.ps1#L1062), [timestamp regression](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L807). |

### Efficiency Outcomes

- Removed redundant post-install byte reads used only for rollback bookkeeping.
- Avoided rewrites of already-restored snapshots, preserving timestamps when attributes also match.
- Reused the scanner's installer AST, matched known names with one matcher, and pruned excluded or
  reparse-point entries during traversal instead of descending through them first.
- Reduced avoidable delegation caused by missing-report assumptions and inconsistent contracts.

No throughput, token-cost, or end-to-end latency improvement is claimed. Test duration is not a
benchmark of installation, discovery, or model execution. The scanner retains snapshots and AST
data for safe application, so its large-repository memory tradeoff remains unmeasured.

## Validation

| Gate | Observed result |
| --- | --- |
| PowerShell 7.6.5, Pester 6.0.1, complete repository suite | 277 passed; 0 failed; 0 skipped |
| Windows PowerShell 5.1.26100.9278, same pinned Pester module and suite | 277 passed; 0 failed; 0 skipped |
| PSScriptAnalyzer 1.25.0 over installer, maintainer scripts, and tests with repository settings | 0 errors and warnings |
| Parse and generation checks | Included in the suite on both hosts; scanner fixtures also exercise parsing and encoding |
| README recommendation and release-note checks after adding Unreleased notes | Passed; recommendation reference and release version unchanged |
| Patch hygiene | `git diff --check` passed before the documentation-only audit was added |

The principal regressions were observed failing before their fixes: duplicate policies, post-write
exceptions, direct rollback under a delete-denying lock, competing agent/settings changes, alias
handoffs, default preference and coordinator reuse, ranking, generated contracts, worker ownership,
uninstall replacement races, scanner content/backup safety, and CI hardening. The final scanner
smart-quote checks first observed two statements instead of one, then passed with the standard
encoder. Not every positive compatibility assertion independently failed; those remain supporting
coverage rather than evidence that a particular historical regression was reproduced.

Suites ran serially across editions because the installer uses a shared named mutex. Pester was
already installed; no dependency installation or live recommendation refresh was needed.

Early integration tests used the real user backup directory before sandboxing. Those runs could
have triggered normal retention; historical backup completeness was not independently audited.
Live agent files and settings were not changed, and no cleanup of the user's backup history was
attempted. Subsequent integration runs used isolated backup storage.

Local workflow assertions are not a hosted Actions or SFTP deployment test. Generated-prompt tests
prove emitted content, not actual model compliance or runtime model identity.

## Council Deliberation

Consensus was limited: the branches had distinct scopes, and shared compatibility and permission
constraints came from their briefs rather than five independent discoveries. Accepted findings
were grounded in coordinator-read source or coordinator-run checks; agreement was not a test.

- **Claude Opus 5 Expert:** identified post-write tracking and direct-restore hazards, plus unchanged
  snapshot churn. Fault injection confirmed the hazards. Its null-state and direct-write fallback
  options were not adopted because they weakened concurrent-edit preservation.
- **GPT-6 Astra Expert:** identified alias/preference/reuse handoff failures and inconsistent agent
  contracts. Public CLI tests confirmed the configuration defects; generated-text tests verified
  the prompt corrections. The compatibility-preserving choice keeps explicit user selections
  ahead of registry defaults and documents runtime limitations.
- **GPT-5.3-Codex Expert:** prioritized destructive ownership false positives, duplicate policy
  keys, and CI credential/dependency-source controls. Behavioral tests confirmed the first two;
  failing workflow assertions confirmed the missing CI declarations.
- **Gemini 3.8 Flash Expert:** prioritized behavioral fault injection and host compatibility rather
  than relying on source-pattern tests. Its broader assertion that placeholder/control-character
  checks were absent was contradicted by existing generated-policy tests. Existing rollback tests
  also reached agent writes, but did not assert the missing agent outcomes.
- **Grok 4.6 Expert:** identified scanner byte/literal hazards and culture-sensitive ordering, both
  reproduced. Its proposed 2 MiB Windows PowerShell JSON limit was not reproduced: both hosts parsed
  a 3 MiB padded value. The read-only recommendation gate was semantic, while a narrower raw-JSON
  comparison remains in update mode.

**Reviewer challenges:** GPT-6 Astra Reviewer supported a conservative ownership signature but
required ambiguity rejection and compatibility with absent/true historical invocation flags. It
also corrected the assumption that uninstall rechecked ownership before deletion, leading to F5.
Claude Opus 5 Reviewer challenged the independence wording: even a scalar reviewer can be routed
elsewhere. That moved the synthesis to a caveat in all roles, not just experts. Its stronger
family-label approach was not adopted as runtime proof; unfamiliar names and platform substitution
remain unknown. Neither review authorized edits by itself, and neither established actual model
independence or universal historical compatibility.

## Council Collaboration Log

| Branch | Assigned scope | Key contribution | Status |
| --- | --- | --- | --- |
| Claude Opus 5 Expert | Installer correctness and durable user-file preservation | Post-write rollback tracking; atomic restore; no-op snapshots | RETURNED |
| GPT-6 Astra Expert | Model handoffs and generated-agent contracts | Canonical identities; configuration precedence; bounded reviewer briefs | RETURNED |
| GPT-5.3-Codex Expert | Ownership/policy trust and release security | Conservative deletion signatures; duplicate-key rejection; CI hardening | RETURNED |
| Gemini 3.8 Flash Expert | Regression and compatibility gaps | Fault-injection and cross-edition validation priorities | RETURNED |
| Grok 4.6 Expert | Discovery/recommendation operations and maintainer tools | Scanner preservation; ordinal ranking; operational hypotheses to probe | RETURNED |
| GPT-6 Astra Reviewer | Ownership compatibility challenge | Legacy flag variants, ambiguous headers, and uninstall race | RETURNED |
| Claude Opus 5 Reviewer | Runtime independence challenge | Scalar reviewer routing caveat | RETURNED |

All Wave 1 reports returned before synthesis and targeted Wave 2 review. No nested expert reviews
were used; the two leaf reviews were coordinator-dispatched after the evidence barrier.

## Conflict Matrix

| ID | Position A | Position B | Settled by or remaining state |
| --- | --- | --- | --- |
| C1 | Claude expert: preseed missing write state with null to make more paths restorable | Coordinator: null permits restoring over another writer; record intended bytes before write | Settled by the post-write and concurrent-edit tests, F1/F3. Concrete byte tracking adopted. |
| C2 | Claude expert: direct-write fallback could improve rollback availability | Coordinator: fail closed when atomic replacement is blocked | Settled by the delete-sharing lock test, F2. The old direct write changed a live target that could not be atomically replaced. |
| C3 | Grok expert: Windows PowerShell JSON parsing has a 2 MiB cap | Coordinator: that specific failure needs an observed run | Both supported hosts parsed a 3 MiB padded value. The specific cap claim was rejected, not all possible size or memory limits. |
| C4 | Grok expert: recommendation gate is sensitive to serialized JSON formatting | Coordinator: distinguish read-only verification from update-mode writes | [Source](../.github/scripts/Update-ModelRecommendation.ps1#L371) compares parsed catalog/recommendation values in read-only mode; [update mode](../.github/scripts/Update-ModelRecommendation.ps1#L495) still compares raw JSON. Narrower issue remains open. |
| C5 | Gemini expert: generation placeholder/control checks are missing from tests | Coordinator: existing generated-policy tests already inject both defects | Settled by [existing tests](../tests/Install-VSCodeCopilotCouncil.Tests.ps1#L1165) and the passing suites. Additional duplicate checks were not added. |
| C6 | Initial synthesis: different configured names and no reviewer fallback adequately qualify independence | Claude reviewer: scalar model values still do not prove actual routing | Synthesis changed to explicit runtime uncertainty in all roles. Source verifies the wording; actual model identity remains unresolved. |
| C7 | Initial ownership proposal: an emitted signature is a practical deletion boundary | Astra reviewer: historical variants and ambiguous YAML need explicit treatment | Bare/quoted duplicates and unsupported header syntax are rejected; absent/true/false invocation flags are tested. Universal legacy compatibility remains open. |

## Evidence Ledger

| Claim | Type | Evidence | Status and limit |
| --- | --- | --- | --- |
| Completed writes are tracked before an exception escapes | EMPIRICAL | F1 regression, both hosts | VERIFIED for the tested fault points |
| Rollback does not truncate the tested locked live target | EMPIRICAL | F2 lock test, both hosts | VERIFIED; unsupported filesystems are not covered |
| Detected competing agent/settings bytes survive rollback | EMPIRICAL | F3 concurrency fixtures | VERIFIED; not an atomic compare-and-swap guarantee |
| Generic worker lookalikes and tested ambiguous headers are not deleted | EMPIRICAL | F4 ownership tests | VERIFIED for tested signatures; authorship is not proven |
| A backup-time replacement survives uninstall | EMPIRICAL | F5 race fixture | VERIFIED; a later compare/delete race remains |
| Duplicate policy names and alias denial cannot pass the tested CLI cases | EMPIRICAL | F6/F7 tests | VERIFIED for tested inputs |
| Default preferences and coordinator fallback reuse reach generated front matter | EMPIRICAL | F11/F12 CLI tests | VERIFIED; interactive and manually edited worker chains have separate limits |
| Recommendation ties are host/culture-stable for the regressions | EMPIRICAL | F13 tests and unchanged reference snapshot | VERIFIED; no global model-quality ranking is asserted |
| Scanner changes constant data without the tested syntax injection or backup corruption | EMPIRICAL | F8/F9 scanner fixtures | VERIFIED for ASCII/smart quotes, multiline data, UTF-8 BOM choices, and existing backups |
| Reviewer constraints and runtime caveats are emitted in the relevant prompts | TEXTUAL / EMPIRICAL | F14-F17 source and generation assertions | VERIFIED as content; compliance UNVERIFIED |
| CI declares repository selection and checkout credential controls | TEXTUAL / EMPIRICAL | F18 workflow source and tests | VERIFIED locally; hosted execution UNVERIFIED |
| Windows PowerShell cannot parse JSON beyond 2 MiB | EMPIRICAL | Successful 3 MiB probe on both hosts | REJECTED by the observed result |
| Read-only recommendation verification compares semantic data | TEXTUAL | C4 cited source | VERIFIED; update-mode no-op behavior still UNVERIFIED |
| All selected runtime models are independent | EMPIRICAL | No runtime identity evidence available | UNVERIFIED; would require trustworthy platform routing evidence |
| These changes improve end-to-end latency or token cost by a measured amount | EMPIRICAL | No controlled benchmark performed | UNVERIFIED; no numerical speedup claim made |

## Dissent Register

| Position not adopted | Evidence or motivation behind it | Disposition |
| --- | --- | --- |
| Restore with null write state or truncate when replacement fails | More paths could appear to recover successfully | Rejected: concurrent-edit and delete-sharing tests demonstrate a higher-cost failure mode. |
| Replace the JSON parser to avoid a 2 MiB limit | Proposed Windows PowerShell compatibility concern | Rejected: the claimed limit failed the local probe. |
| Treat configured families as strong evidence of actual independent reviewers | Different providers can broaden perspectives | Retained as a preference only. Neither names nor absent fallback lists prove runtime routing. |
| Broaden a reviewer search when the brief omits scope | Could recover context missing from a poor delegation | Rejected for authorization ambiguity; the reviewer now names the missing boundary. |
| Pin registry preferences ahead of explicit user choices | A registry pin could be interpreted as mandatory | Not adopted: explicit CLI/picker/reuse intent is preserved; precedence is documented. |
| Treat release-only placeholder checks as a missing Pester feature | Concern about fragile prompt interpolation | Rejected as a broad claim; existing tests already exercise those failures. |
| Add arbitrary database-size and changelog-section caps | Bound memory or parser work | Deferred: no representative failure or justified threshold was established. |
| Change cache-profile preference or add a persistent interop DLL cache | Potential discovery speed or catalog freshness | Deferred: no measured benefit; profile selection and process compatibility are existing behavior. |

## Unresolved Risks and Deferred Checks

| Risk or suggestion | Why it remains open; impact | Exact next check or action |
| --- | --- | --- |
| Runtime model routing and prompt compliance | Text generation cannot verify the selected runtime family or stop/delegation obedience. | Run opt-in VS Code scenarios for missing primaries, scalar reviewers, Auto, stop questions, and incomplete directives; inspect trustworthy routing/status evidence. |
| Historical ownership compatibility | Tested generated headers include invocation flags absent, true, and false, but not every historical release. Conservative rejection may leave old workers behind. | Collect authentic headers from supported release tags and add read-only ownership fixtures before broadening acceptance. |
| Filesystem races and nonlocal replacement semantics | Byte comparisons narrow races but are not atomic compare-and-swap or compare-and-delete. Locked/network targets can prevent recovery. | Fault-inject changes after the last comparison; separately test supported SMB/filesystem combinations and inspect byte-exact recovery artifacts. |
| Scanner multi-file partial application | Each replacement is atomic; a later failure does not roll back earlier files. Interpolated strings are outside its constant-literal matcher, and non-PowerShell files use text matching. | Run an isolated multi-file failure fixture and inspect backups/diff. For a future structured format guarantee, validate or parse JSON/YAML rather than promising syntax preservation from text matching. |
| Scanner invalid UTF-8 and traversal coverage | Invalid UTF-8 files are warned and skipped; reparse-point entries are not traversed. The scan is not proof of complete coverage of every reachable path. | Test an invalid-byte fixture, linked subdirectories, and explicit linked roots against the intended support policy. |
| Recommendation update-mode no-op churn | Raw JSON comparison can request writes for formatting-only differences; all three representations are then written. The read-only gate is not affected by that comparison. | Build an offline fake-catalog fixture, alternate `-Update` between the two hosts, and compare bytes/timestamps before changing update logic. No live catalog update was attempted. |
| Cache-copy cost and freshness | Blob limits do not establish a bound for copying a large database; Stable-first lookup does not prove the freshest profile wins. No workload data justified changing either behavior. | Benchmark representative database sizes and profile timestamps, including busy SQLite/WAL cases; select a limit or profile policy from measurements. |
| Allowlist validator duplicate expectations and graph closure | Emitter and validator deduplication can diverge for a synthetic duplicate list; production rosters remain unique. Whole-roster closure validation was not added. | Pass duplicate and missing target names through generation/validation fixtures before changing the validator contract. |
| `Get-VSCodeStatus` and other behavioral test gaps | Some existing helper tests check source or string operations. Mutex contention, slug collisions, and additional provenance/CLI combinations deserve independent behavioral fixtures. | Add one actual helper-result fixture and a controlled two-process mutex test; separately exercise colliding slugs and release provenance failures without publication. |
| Rare path, lock, and attribute cases | UNC fixed-point and bracket-path backup concerns were not reproduced as failures. No transient-lock retry policy or arbitrary attribute filtering was justified. | Test real supported UNC roots, bracket-containing paths, read-only files, concurrent parent creation, and retained recovery backups in isolated directories. |
| Release deployment | Local source and structure tests do not exercise hosted permissions, registry availability, or SFTP promotion. | Run the repository's validation workflow; perform deployment validation only with explicit publishing authorization. |
| Early test backup history | Before sandboxing, test installs used real backup storage and may have invoked retention. Prior completeness cannot be reconstructed from current test results. | Compare existing backup inventory with an independently retained pre-review backup inventory, if available; do not delete recovery folders as cleanup. |

## Decision

Ship the source changes through the normal review and release process, keeping the known limits
explicit. The reproduced high-impact defects are covered by failing-then-passing regressions, the
supported host suites pass, and speculative performance or compatibility changes were not mixed
into the fixes. Apply the new generated-agent instructions through a deliberate installer rerun
after reviewing the patch; the running user configuration was not changed by this review.

## Publication Follow-up

On September 7, 2026, the user requested publication to GitHub. The read-only pre-push gate found
that the live profile had grown from 24 to 26 cached models and now recommended GPT-6 Astra and
Gemini 3.8 Flash. The fallback catalog was extended with those names and their observed categories
(`powerful` and `versatile` respectively), without removing older entries or changing the unattended
default roster. The maintainer tool refreshed the reference snapshot, README example, review date,
and Last Modified metadata; the release version remains 5.18.0.

The contraction guard passed without an override. The live gate and all three offline reference
consistency tests then passed. This refresh does not resolve the separately documented possibility
of formatting-only update churn across hosts, and it does not establish runtime model identity.