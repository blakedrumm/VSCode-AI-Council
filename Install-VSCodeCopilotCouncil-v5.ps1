<#
.SYNOPSIS
    Installs an adaptive multi-model GitHub Copilot agent system for Visual Studio Code.

.DESCRIPTION
    Creates a single user-selectable coordinator agent that automatically chooses the
    cheapest strategy capable of producing a correct answer, plus one hidden expert and
    one hidden leaf reviewer for each configured model.

    Installed agents:

        Multi-Model Engineering Council      (user-selectable coordinator)
        <Model> Expert                       (hidden worker, one per model)
        <Model> Reviewer                     (hidden leaf reviewer, one per model)

    The coordinator replaces the previous Council / Debate / Parallel Team split. It
    classifies each request once and selects one of six tiers:

        Tier 0  Answer directly, no subagents
        Tier 1  One expert
        Tier 2  Two experts in parallel
        Tier 3  Adversarial debate with nested cross-model review
        Tier 4  One expert per configured model in parallel
        Tier 5  Unconstrained full-team brainstorm, only on an explicit keyword

    Controlled nested cross-model communication:

        <Model A> Expert -> may invoke exactly one reviewer from a different model, once
        <Model B> Expert -> may invoke exactly one reviewer from a different model, once

    Reviewers are leaf agents. They have no subagent tool, so nesting depth is capped at
    two levels and GPT -> Claude -> GPT -> Claude recursion is impossible.

    Each expert is assigned a distinct primary lens so that parallel workers do not
    duplicate each other:

        1. Implementation and correctness
        2. Architecture and maintainability
        3. Security and reliability
        4. Testing and regression risk
        5. Performance and operations

    The installer also enables:

        chat.subagents.allowInvocationsFromSubagents = true

    in the VS Code user settings file. That setting is global, so it enables nested subagents
    for every agent you use, not only for this council.

    The generated agents narrate their work. The coordinator announces the tier, the experts it
    is dispatching, and the question each one was asked before it invokes anything, and its final
    answer carries a council deliberation section holding each expert's stance, the conflicts
    between them, and the evidence that settled each one.

    The coordinator tracks each run as a todo list and classifies a mid-run user interjection as
    a redirect, a refinement, or a detour, so a run interrupted by a steering message is resumed
    from the experts that already returned instead of being silently dropped.

    When an earlier installation is found in the target agent directory, the installer reads the
    models and coordinator model back out of the installed coordinator agent and offers to reuse
    them, so a re-run does not require re-picking the same models.

    The model picker also marks a recommended set detected from the live catalog: the newest model
    from each vendor that VS Code publishes as powerful or versatile, since a peer review is only
    independent across training lineages. Models VS Code publishes as lightweight and the Auto
    router are excluded. Version numbers are only compared inside one vendor, because they mean
    nothing across vendors.

    The size classification is read from the model cache rather than guessed from the name, so a
    model whose name carries no size hint is still classified correctly. When no cache is available,
    for example with -ModelCatalog, the picker falls back to name-based rules and the recommendation
    is correspondingly weaker. The picker prints the date the rule was last revised alongside it.

    Existing agent files and VS Code settings are backed up before modification and restored if
    agent activation fails before the new roster is fully validated. Older backup folders beyond the
    newest few are pruned after a successful install.

.PARAMETER Scope
    Determines where the custom agent files are installed.

    User:
        Installs to ~/.copilot/agents, making the agents available in every workspace.

    Workspace:
        Installs to <WorkspacePath>/.github/agents, scoping the agents to one workspace.

    The nested-subagent VS Code setting is still applied to the user settings file unless
    -VSCodeSettingsPath or -SkipVSCodeSetting is used.

.PARAMETER WorkspacePath
    Required when -Scope Workspace is used.

.PARAMETER Models
    One to five model names to build agents for. When omitted, the installer prompts.

    When omitted and an earlier installation exists in the target agent directory, the prompt
    first offers the models that installation used.

    Order matters. Position determines which expert lens each model receives.

    The names must match the model names shown in the Visual Studio Code model picker.
    The installer reads the live list from the VS Code model cache, so the prompt shows
    the models your GitHub Copilot account can actually use.

    Avoid Auto here. It is a router, so two Auto experts can be routed onto the same
    underlying model, which defeats the independent cross-model review the council
    relies on. Auto is fine for -CoordinatorModel.

.PARAMETER CoordinatorModel
    Model used by the Multi-Model Engineering Council coordinator.

    Defaults to the first entry in -Models.

.PARAMETER ModelCatalog
    Overrides model discovery with an explicit list of models for the interactive picker.

.PARAMETER VSCodeSettingsPath
    Optional explicit path to the VS Code settings.json file.

    If not specified, the script first checks:

        %APPDATA%\Code\User\settings.json
        %APPDATA%\Code - Insiders\User\settings.json

    If neither exists, it defaults to the stable path.

.PARAMETER SkipVSCodeSetting
    Prevents the script from changing the VS Code
    chat.subagents.allowInvocationsFromSubagents setting.

.PARAMETER SkipUpdateCheck
    Prevents the script from contacting GitHub to compare its own version against the published one.

    The check reads the latest release tag from the GitHub API. It never downloads or runs release
    assets or scripts, and a failed or blocked check never stops the installation.

.PARAMETER NonInteractive
    Suppresses all prompts. Requires -Models, or reuses the configuration of an earlier
    installation in the target agent directory, or falls back to the built-in default pair.

.PARAMETER OpenInVSCode
    Opens the installed coordinator agent file and the VS Code settings file after
    installation when a standard VS Code installation and its CLI are detected.

.EXAMPLE
    .\Install-VSCodeCopilotCouncil-v5.ps1

    Prompts for the models to use.

.EXAMPLE
    .\Install-VSCodeCopilotCouncil-v5.ps1 -Models 'GPT-5.6 Sol', 'Claude Opus 5'

.EXAMPLE
    .\Install-VSCodeCopilotCouncil-v5.ps1 `
        -Models 'GPT-5.6 Sol', 'Claude Opus 5', 'Gemini 3 Pro' `
        -CoordinatorModel 'Claude Opus 5' `
        -OpenInVSCode

.EXAMPLE
    .\Install-VSCodeCopilotCouncil-v5.ps1 `
        -Scope Workspace `
        -WorkspacePath 'C:\GitHub\MyProject' `
        -NonInteractive

.NOTES
    Author:
        Blake Drumm (blakedrumm@microsoft.com)

    Date Created:
        August 6th, 2026

    Last Modified:
        August 11th, 2026

    Version:
        5.7.4

    Compatible with:
        Windows PowerShell 5.1
        PowerShell 7+

    Requires:
        Visual Studio Code
        GitHub Copilot
        GitHub Copilot Chat / Agent support
        Access to the configured models

    Important:
        The script does not enable global tool auto-approval.
        The script does not enable unrestricted recursive agents.
        The update check reads release metadata but never downloads or executes release assets or
        scripts. It prints a link, so any upgrade stays a deliberate act by the user.

    License:
        MIT License

        Copyright (c) 2026 Microsoft

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
#>

[CmdletBinding()]
param
(
    [Parameter()]
    [ValidateSet('User', 'Workspace')]
    [string]
    $Scope = 'User',

    [Parameter()]
    [string]
    $WorkspacePath,

    # The upper bound must equal $LensCatalog.Count; an attribute argument cannot reference a variable.
    [Parameter()]
    [ValidateCount(1, 5)]
    [string[]]
    $Models,

    [Parameter()]
    [string]
    $CoordinatorModel,

    [Parameter()]
    [string[]]
    $ModelCatalog,

    [Parameter()]
    [string]
    $VSCodeSettingsPath,

    [Parameter()]
    [switch]
    $SkipVSCodeSetting,

    [Parameter()]
    [switch]
    $SkipUpdateCheck,

    [Parameter()]
    [switch]
    $NonInteractive,

    [Parameter()]
    [switch]
    $OpenInVSCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================================
# HOW THIS SCRIPT IS ORGANIZED
#
#   1. Script configuration    Constants, the lens catalog, and the update-check target.
#   2. Console output          Timestamped logging and the step progress counter.
#   3. File helpers            Atomic UTF-8 writes and timestamped backups.
#   4. Small helpers           Name validation, slug generation, safe property access.
#   5. Update check            Reads the published version from GitHub. Never runs remote code.
#   6. Model discovery         Reads the live model list from the VS Code SQLite state database.
#   7. Previous installation   Recovers the last-used models from the installed agent files.
#   8. Recommendation          Picks a vendor-diverse roster from whatever the catalog offers.
#   9. Interactive prompts     The model picker and the coordinator picker.
#  10. VS Code settings        A comment-preserving edit of the user's settings.json.
#  11. Agent content           Builds the markdown body of every agent file.
#  12. Install and validate    Writes the agent files, then re-reads them to prove they are sane.
#  13. Environment detection   Finds VS Code and the Copilot extensions.
#  14. Installation            The top-level flow. This is where execution actually begins.
#
# Sections 1 through 13 only define constants and functions. Nothing happens until section 14.
# =============================================================================================

#region 1. Script configuration

# The coordinator is the only agent the user ever selects. Everything else is a hidden worker.
$CoordinatorAgentName = 'Multi-Model Engineering Council'
$CoordinatorFileName = 'multi-model-engineering-council.agent.md'

# Declared once so the generated front matter and its post-install assertion cannot drift apart.
$ReviewerAgentTools = @('read', 'search', 'web')
$ExpertAgentTools = @('agent', 'read', 'search', 'web')
$CoordinatorAgentTools = @('agent', 'read', 'search', 'edit', 'execute', 'web', 'todo')

# Rendered into the expert, reviewer, and coordinator prompts. Two hand-maintained copies had
# already drifted at item 6, which is the kind of disagreement the list itself exists to settle.
$EvidenceHierarchy = @(
    'Repository source code',
    'Reproducible tests',
    'Runtime, compiler, or interpreter behavior',
    'Official documentation',
    'API specifications',
    'Platform diagnostics and logs',
    'Logical consistency',
    'Established engineering practice'
)

$EvidenceHierarchyText = (0..($EvidenceHierarchy.Count - 1) | ForEach-Object { "$($_ + 1). $($EvidenceHierarchy[$_])" }) -join "`n"

# Backup folders are timestamped per run, so without a cap they accumulate for the life of the profile.
$BackupRetentionCount = 10

# Keep this in sync with the Version entry in the .NOTES block. The update check compares it against
# the same constant in the published copy, so it is the single source of truth for the version.
$ScriptVersion = '5.7.4'

# Change this to your own owner/repo to point the update check somewhere else.
$UpdateRepository = 'blakedrumm/VSCode-AI-Council'

# Only used when the live model list cannot be read from the VS Code cache. These names will go
# stale as models are retired, which is exactly why the cache is preferred over this list.
$DefaultModelCatalog = @(
    'Claude Haiku 4.5',
    'Claude Opus 5',
    'Claude Sonnet 5',
    'Gemini 3.5 Flash',
    'GPT-5 mini',
    'GPT-5.6 Sol',
    'GPT-5.6 Terra',
    'Grok 4.5'
)

# The last-resort roster for a fully unattended run with no models given and nothing installed.
$DefaultModels = @('GPT-5.6 Sol', 'Claude Opus 5')

# Shown next to the recommended set so a stale rule is visible rather than silently trusted.
$RecommendationDate = 'August 10, 2026'

# Position in this list determines each expert's primary lens, so parallel workers never overlap.
# The Focus entries are pasted verbatim into the generated expert agent, which is what actually
# steers that model's attention. Reordering this list silently reassigns every lens.
$LensCatalog = @(
    [PSCustomObject]@{
        Title = 'Implementation and correctness'
        Focus = @(
            'root cause analysis',
            'implementation approach and code paths',
            'API and library behavior',
            'error handling and edge cases',
            'runtime and compiler behavior',
            'backward compatibility'
        )
    },
    [PSCustomObject]@{
        Title = 'Architecture and maintainability'
        Focus = @(
            'system and module boundaries',
            'design consistency with the existing codebase',
            'dependency direction and coupling',
            'integration design',
            'long-term consequences of the change',
            'readability and maintenance cost'
        )
    },
    [PSCustomObject]@{
        Title = 'Security and reliability'
        Focus = @(
            'OWASP Top 10 exposure',
            'authentication, authorization, and trust boundaries',
            'secret, token, and credential handling',
            'input validation and injection paths',
            'failure isolation and blast radius',
            'unsafe defaults and privilege escalation'
        )
    },
    [PSCustomObject]@{
        Title = 'Testing and regression risk'
        Focus = @(
            'test coverage gaps',
            'regression surface of the proposed change',
            'boundary and off-by-one conditions',
            'failure and rollback paths',
            'concurrency, ordering, and idempotency',
            'the exact validation commands to run'
        )
    },
    [PSCustomObject]@{
        Title = 'Performance and operations'
        Focus = @(
            'algorithmic, allocation, and I/O cost',
            'latency, throughput, and resource limits',
            'caching and batching opportunities',
            'observability and diagnostics',
            'deployment, migration, and rollback',
            'behavior under load and degradation'
        )
    }
)

# One lens per model, so the catalog length is the real ceiling. A sixth model would have to reuse
# a lens, and two experts would then duplicate each other's work.
$MaxModelCount = $LensCatalog.Count

#endregion

#region 2. Console output and progress

# Every status line in the script funnels through here so the console keeps one consistent, timestamped style.
function Write-Console
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Detail')]
        [string]
        $Level = 'Info'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Line = '{0} - {1}' -f $Timestamp, $Message

    switch ($Level)
    {
        'Success'
        {
            Write-Host $Line -ForegroundColor Green
        }
        'Warning'
        {
            Write-Host $Line -ForegroundColor Yellow
        }
        'Detail'
        {
            Write-Host $Line -ForegroundColor DarkGray
        }
        default
        {
            Write-Host $Line
        }
    }
}

# Renders a duration at a sensible precision. Sub-second steps read better in milliseconds than
# as "0.04 s", and a long run reads better as mm:ss than as a four-digit second count.
function Format-Elapsed
{
    param
    (
        [Parameter(Mandatory = $true)]
        [TimeSpan]
        $Elapsed
    )

    if ($Elapsed.TotalSeconds -lt 1)
    {
        return ('{0:N0} ms' -f $Elapsed.TotalMilliseconds)
    }

    if ($Elapsed.TotalMinutes -lt 1)
    {
        return ('{0:N2} s' -f $Elapsed.TotalSeconds)
    }

    return ('{0:mm\:ss}' -f $Elapsed)
}

# Step progress exists purely so the installer never looks frozen. The step list is built at
# run time from the parameters actually in play, so the counter always reaches its own total
# even when branches such as -SkipVSCodeSetting remove steps.
$script:InstallProgressState = $null

# Records the planned step list and decides whether a graphical progress bar is appropriate.
# Call this once, before the first Start-InstallStep.
function Initialize-InstallProgress
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]]
        $StepNames
    )

    $UseProgressBar = $false

    if ([Environment]::UserInteractive)
    {
        try
        {
            # Write-Progress is decoration only; it is skipped when output is piped to a file or CI log.
            $UseProgressBar = -not [Console]::IsOutputRedirected
        }
        catch
        {
            $UseProgressBar = $false
        }
    }

    $script:InstallProgressState = [PSCustomObject]@{
        Total = $StepNames.Count
        Index = 0
        Timer = $null
        UseProgressBar = $UseProgressBar
        Activity = 'Installing adaptive multi-model Copilot council'
    }

    Write-Verbose ('Planned steps: {0}' -f ($StepNames -join ' | '))
}

# Announces the start of a step, bumps the counter, and starts the per-step timer.
# Every Start-InstallStep must be matched by a Complete-InstallStep or the counter will drift.
function Start-InstallStep
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    if ($null -eq $script:InstallProgressState)
    {
        return
    }

    $script:InstallProgressState.Index++
    $script:InstallProgressState.Timer = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Console ('[{0}/{1}] {2}...' -f $script:InstallProgressState.Index, $script:InstallProgressState.Total, $Name)

    if ($script:InstallProgressState.UseProgressBar)
    {
        $Percent = [int](($script:InstallProgressState.Index - 1) * 100 / [Math]::Max(1, $script:InstallProgressState.Total))
        Write-Progress -Activity $script:InstallProgressState.Activity -Status ('Step {0} of {1}: {2}' -f $script:InstallProgressState.Index, $script:InstallProgressState.Total, $Name) -PercentComplete $Percent
    }
}

# Stops the per-step timer and prints how long the step took.
function Complete-InstallStep
{
    if ($null -eq $script:InstallProgressState -or $null -eq $script:InstallProgressState.Timer)
    {
        return
    }

    $script:InstallProgressState.Timer.Stop()

    Write-Console ('[{0}/{1}] done in {2}' -f $script:InstallProgressState.Index, $script:InstallProgressState.Total, (Format-Elapsed -Elapsed $script:InstallProgressState.Timer.Elapsed)) -Level 'Success'
    $script:InstallProgressState.Timer = $null
}

# Clears the progress bar at the end of the run so it does not linger in the console.
function Complete-InstallProgress
{
    if ($null -eq $script:InstallProgressState)
    {
        return
    }

    if ($script:InstallProgressState.UseProgressBar)
    {
        Write-Progress -Activity $script:InstallProgressState.Activity -Completed
    }
}

#endregion

#region 3. File writing and backup

# Collapses CRLF, lone CR, and LF down to one style, then re-emits the platform's line ending.
# Without this, content assembled from here-strings and joined arrays ends up with mixed endings.
function ConvertTo-NormalizedText
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    $Normalized = $Text -replace "`r`n", "`n"
    $Normalized = $Normalized -replace "`r", "`n"

    return ($Normalized -replace "`n", [Environment]::NewLine)
}

# Writes UTF-8 without a byte order mark, which is what VS Code expects for agent files.
# A BOM would end up inside the YAML front matter and break the first key.
function Write-Utf8File
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Content,

        # Set when editing a file the script does not own, so its existing line endings survive.
        [Parameter()]
        [switch]
        $PreserveLineEndings
    )

    $ParentDirectory = Split-Path -Path $Path -Parent

    if (-not [string]::IsNullOrWhiteSpace($ParentDirectory))
    {
        if (-not (Test-Path -LiteralPath $ParentDirectory))
        {
            New-Item -Path $ParentDirectory -ItemType Directory -Force | Out-Null
        }
    }

    $OutputContent = $Content

    if (-not $PreserveLineEndings)
    {
        $OutputContent = ConvertTo-NormalizedText -Text $Content
    }

    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

    # Written to a sibling temp file and swapped in, so an interrupted run cannot truncate the target.
    $TemporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $ReplacedPath = "$Path.$([guid]::NewGuid().ToString('N')).old"
    $KeepReplacedPath = $false

    try
    {
        [System.IO.File]::WriteAllText($TemporaryPath, $OutputContent, $Utf8WithoutBom)

        if ([System.IO.File]::Exists($Path))
        {
            try
            {
                # Replace is atomic, but it needs both files on one volume and some synced folders refuse it.
                [System.IO.File]::Replace($TemporaryPath, $Path, $ReplacedPath, $true)
            }
            catch
            {
                $ReplaceError = $_.Exception.Message
                $TargetMatchesOutput = $false

                if ([System.IO.File]::Exists($Path))
                {
                    try
                    {
                        # Compared as bytes: a BOM or an invalid sequence can decode equal to the
                        # desired text while the file on disk is not what was written.
                        $ActualBytes = [System.IO.File]::ReadAllBytes($Path)
                        $ExpectedBytes = $Utf8WithoutBom.GetBytes($OutputContent)

                        $TargetMatchesOutput = [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($ActualBytes, $ExpectedBytes)
                    }
                    catch
                    {
                        $TargetMatchesOutput = $false
                    }
                }

                if ($TargetMatchesOutput)
                {
                    # Some filesystem filters report a metadata error after the data swap completed.
                    Write-Verbose "Atomic replace completed for $Path despite a reported error. $ReplaceError"
                }
                else
                {
                    if (-not [System.IO.File]::Exists($Path) -and [System.IO.File]::Exists($ReplacedPath))
                    {
                        try
                        {
                            [System.IO.File]::Move($ReplacedPath, $Path)
                        }
                        catch
                        {
                            $KeepReplacedPath = $true
                        }
                    }
                    elseif ([System.IO.File]::Exists($ReplacedPath))
                    {
                        $KeepReplacedPath = $true
                    }

                    $RecoveryText = if ($KeepReplacedPath) { " Recovery copy: $ReplacedPath" } else { '' }
                    throw "Atomic replacement failed for $Path. The live file was not overwritten directly.$RecoveryText $ReplaceError"
                }
            }
        }
        else
        {
            [System.IO.File]::Move($TemporaryPath, $Path)
        }
    }
    finally
    {
        Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue

        if (-not $KeepReplacedPath)
        {
            Remove-Item -LiteralPath $ReplacedPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Reads UTF-8 with invalid-byte detection. Windows PowerShell 5.1 otherwise treats BOM-less files
# as the active ANSI code page, while the permissive .NET decoder silently inserts U+FFFD.
function Read-Utf8File
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    $StrictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)

    try
    {
        return [System.IO.File]::ReadAllText($Path, $StrictUtf8)
    }
    catch [System.Text.DecoderFallbackException]
    {
        throw "File is not valid UTF-8 and was not read: $Path"
    }
}

# Captures exact bytes and basic attributes for rollback without interpreting the file's encoding.
function Get-FileStateSnapshot
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path
    )

    $Exists = [System.IO.File]::Exists($Path)

    return [PSCustomObject]@{
        Path = $Path
        Existed = $Exists
        Bytes = $(if ($Exists) { [System.IO.File]::ReadAllBytes($Path) } else { $null })
        Attributes = $(if ($Exists) { [System.IO.File]::GetAttributes($Path) } else { $null })
    }
}

# Restores a snapshot taken by Get-FileStateSnapshot. This is only used after a failed commit.
function Restore-FileStateSnapshot
{
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Snapshot
    )

    if ($Snapshot.Existed)
    {
        $ParentDirectory = Split-Path -Path $Snapshot.Path -Parent

        if (-not (Test-Path -LiteralPath $ParentDirectory))
        {
            New-Item -Path $ParentDirectory -ItemType Directory -Force | Out-Null
        }

        if ([System.IO.File]::Exists($Snapshot.Path))
        {
            [System.IO.File]::SetAttributes($Snapshot.Path, [System.IO.FileAttributes]::Normal)
        }

        [System.IO.File]::WriteAllBytes($Snapshot.Path, $Snapshot.Bytes)
        [System.IO.File]::SetAttributes($Snapshot.Path, $Snapshot.Attributes)
    }
    elseif ([System.IO.File]::Exists($Snapshot.Path))
    {
        [System.IO.File]::SetAttributes($Snapshot.Path, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($Snapshot.Path)
    }
}

# Copies a file into the run's backup folder before it is overwritten or deleted.
# The parent folder name is prefixed onto the copy so files with the same name never collide.
function Backup-ExistingFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string]
        $BackupDirectory
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        return
    }

    if (-not (Test-Path -LiteralPath $BackupDirectory))
    {
        New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
    }

    $FileName = Split-Path -Path $Path -Leaf
    $ParentName = Split-Path -Path (Split-Path -Path $Path -Parent) -Leaf

    if ([string]::IsNullOrWhiteSpace($ParentName))
    {
        $ParentName = 'root'
    }

    $SafeParentName = $ParentName -replace '[^A-Za-z0-9._-]', '_'
    $BackupPath = Join-Path -Path $BackupDirectory -ChildPath "$SafeParentName-$FileName"

    Copy-Item -LiteralPath $Path -Destination $BackupPath -Force

    Write-Console "Backed up $FileName to $BackupPath" -Level 'Detail'
}

# Removes backup folders beyond the newest $KeepCount, never the folder this run is still using.
function Remove-ExpiredBackup
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $BackupRoot,

        [Parameter(Mandatory = $true)]
        [string]
        $CurrentBackupDirectory,

        [Parameter(Mandatory = $true)]
        [int]
        $KeepCount
    )

    if (-not (Test-Path -LiteralPath $BackupRoot))
    {
        return
    }

    # The folder name is a sortable timestamp, so newest-first is a plain descending name sort.
    $CurrentName = Split-Path -Path $CurrentBackupDirectory -Leaf

    # This run's folder is filtered out below, so it has to be charged against the cap here or the
    # installer would keep KeepCount plus one.
    $KeepBesidesCurrent = $KeepCount

    if (Test-Path -LiteralPath $CurrentBackupDirectory)
    {
        $KeepBesidesCurrent = [Math]::Max(0, $KeepCount - 1)
    }

    $Expired = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^v5_\d{8}_\d{9}$' -and $_.Name -ne $CurrentName } |
            Sort-Object -Property 'Name' -Descending |
            Select-Object -Skip $KeepBesidesCurrent)

    $Removed = 0

    foreach ($Directory in $Expired)
    {
        try
        {
            Remove-Item -LiteralPath $Directory.FullName -Recurse -Force
            $Removed++
        }
        catch
        {
            Write-Verbose "Could not remove the old backup folder $($Directory.FullName). $($_.Exception.Message)"
        }
    }

    if ($Removed -gt 0)
    {
        Write-Console "Removed $Removed backup folder(s) beyond the newest $KeepCount." -Level 'Detail'
    }
}

#endregion

#region 4. Small helpers

# Rejects a model name that would corrupt the generated agent file. This runs on anything the
# user types, anything read back from a previous install, and anything read from the model cache.
function Test-ModelName
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Name
    )

    if ([string]::IsNullOrWhiteSpace($Name))
    {
        return $false
    }

    if ($Name.Length -gt 100 -or $Name -cne $Name.Trim())
    {
        return $false
    }

    # These characters would break the YAML front matter the agent files depend on.
    # U+0085, U+2028, and U+2029 end a line for a YAML parser but not for .NET's (?m)^ anchor, so an injected key would slip past Test-AgentFile.
    # Unicode format and surrogate code points are rejected to prevent invisible or malformed names.
    if ($Name -match '[:"''\\{}\[\]#,]' -or $Name -match '[\x00-\x1F\u0085\u2028\u2029\p{Cf}\p{Cs}]')
    {
        return $false
    }

    return ($Name -match '^[A-Za-z0-9]')
}

# Turns a model name into a safe file name fragment, for example "GPT-5.6 Sol" to "gpt-5-6-sol".
function ConvertTo-AgentSlug
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Text
    )

    $Slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $Slug = $Slug.Trim('-')

    if ([string]::IsNullOrWhiteSpace($Slug))
    {
        $Slug = 'model'
    }

    return $Slug
}

# Reads a property that may not exist. Set-StrictMode turns a plain $Object.Missing into a
# terminating error, so every access to parsed JSON has to go through this.
function Get-PropertyValue
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    if ($null -eq $InputObject)
    {
        return $null
    }

    $Property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $Property)
    {
        return $null
    }

    return $Property.Value
}

#endregion

#region 5. Update check

# Returns the version string published for this script, or $null if it cannot be determined.
#
# Every failure path returns $null rather than throwing, because a blocked network, a proxy, or
# a deleted repository must never stop someone from installing.
function Get-PublishedScriptVersion
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Repository,

        [Parameter(Mandatory = $true)]
        [int]
        $TimeoutSeconds
    )

    # Only release metadata is read. Release assets and scripts are never downloaded or executed,
    # so upgrading stays a manual action the user can review first.
    $PreviousProtocol = [Net.ServicePointManager]::SecurityProtocol
    $ProgressPreference = 'SilentlyContinue'

    try
    {
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # Windows PowerShell 5.1 can still negotiate TLS 1.0, which GitHub rejects outright.
            [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol -bor [Net.SecurityProtocolType]::Tls12
        }

        $Headers = @{
            'User-Agent' = 'Install-VSCodeCopilotCouncil'
            'Accept' = 'application/vnd.github+json'
        }

        try
        {
            $Release = Invoke-RestMethod `
                -Uri "https://api.github.com/repos/$Repository/releases/latest" `
                -Headers $Headers `
                -TimeoutSec $TimeoutSeconds `
                -ErrorAction Stop

            $Tag = [string](Get-PropertyValue -InputObject $Release -Name 'tag_name')
            $TagMatch = [regex]::Match($Tag, '([0-9]+(?:\.[0-9]+){1,3})')

            if ($TagMatch.Success)
            {
                return $TagMatch.Groups[1].Value
            }
        }
        catch
        {
            Write-Verbose "No published release metadata could be read for $Repository. $($_.Exception.Message)"
        }
    }
    catch
    {
        Write-Verbose "Update check failed. $($_.Exception.Message)"
    }
    finally
    {
        [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol
    }

    return $null
}

#endregion

#region 6. VS Code model catalog discovery

# Compiles a tiny P/Invoke wrapper around the SQLite library that ships with Windows.
# Returns $true when the type is available, $false when the platform cannot provide it.
#
# This exists because the VS Code model list lives in a SQLite database and there is no
# supported command-line way to read it.
function Initialize-SqliteInterop
{
    # The versioned type name prevents a wrapper loaded by an older development build from being
    # mistaken for this contract in a long-lived, dot-sourced PowerShell session.
    if ('VSCodeCouncil.SqliteCacheV1' -as [type])
    {
        return $true
    }

    # Bound to the absolute System32 path so the loader cannot resolve a same-named DLL from PATH or the working directory.
    $SqliteDllPath = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'winsqlite3.dll'

    if (-not (Test-Path -LiteralPath $SqliteDllPath -PathType Leaf))
    {
        Write-Verbose "The system SQLite library is unavailable: $SqliteDllPath"
        return $false
    }

    # DllImport needs a compile-time constant, and the C# literal needs its backslashes escaped.
    $DllImportPath = $SqliteDllPath.Replace('\', '\\')

    try
    {
        Write-Console 'Compiling SQLite interop. The first run in a new PowerShell process can take a few seconds.' -Level 'Detail'

        Add-Type -Namespace 'VSCodeCouncil' -Name 'SqliteCacheV1' -MemberDefinition @"
private const string SqliteLibrary = "$DllImportPath";

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_open_v2", CallingConvention = CallingConvention.Cdecl)]
public static extern int Open(byte[] filename, out IntPtr db, int flags, IntPtr vfs);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_prepare_v2", CallingConvention = CallingConvention.Cdecl)]
public static extern int Prepare(IntPtr db, byte[] sql, int byteCount, out IntPtr statement, IntPtr tail);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_step", CallingConvention = CallingConvention.Cdecl)]
public static extern int Step(IntPtr statement);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_column_bytes", CallingConvention = CallingConvention.Cdecl)]
public static extern int ColumnBytes(IntPtr statement, int column);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_column_blob", CallingConvention = CallingConvention.Cdecl)]
public static extern IntPtr ColumnBlob(IntPtr statement, int column);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_finalize", CallingConvention = CallingConvention.Cdecl)]
public static extern int Release(IntPtr statement);

[DllImport(SqliteLibrary, EntryPoint = "sqlite3_close", CallingConvention = CallingConvention.Cdecl)]
public static extern int Close(IntPtr db);
"@

        return $true
    }
    catch
    {
        Write-Verbose "winsqlite3.dll is unavailable. $($_.Exception.Message)"
        return $false
    }
}

# Windows PowerShell 5.1 emits a top-level JSON array as one nested Object[] when ConvertFrom-Json
# is called directly inside @(). Assigning first lets the second @() normalize both editions alike.
function ConvertFrom-ModelCacheJson
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Json
    )

    $ParsedValue = $Json | ConvertFrom-Json

    return @($ParsedValue)
}

# Reads the cached model list out of one VS Code state database and returns a Name plus Category
# record for every model that is user-selectable and supports agent mode.
#
# Category is the size class VS Code publishes: powerful, versatile, or lightweight. The
# recommendation logic depends on it, because a model name alone does not reveal its size.
#
# The result is wrapped in an object because a bare empty array collapses to $null on return, and
# the caller has to tell an unreadable snapshot from one that simply held no agent-capable model.
function Get-CachedModelRecord
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $StatePath
    )

    # VS Code keeps the state database open, and large values span overflow pages,
    # so the file has to be copied and read through SQLite rather than scanned as text.
    $TempCopy = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-state-$([guid]::NewGuid().ToString('N')).vscdb"
    $Database = [IntPtr]::Zero
    $Statement = [IntPtr]::Zero

    # A torn copy can prepare, step, or parse badly without throwing. Those are read failures, not an
    # empty cache, and only a failure verdict makes the caller retry with a fresh snapshot.
    $OperationalFailure = $false
    $SqliteRow = 100
    $SqliteDone = 101

    try
    {
        Copy-Item -LiteralPath $StatePath -Destination $TempCopy -Force

        # Recent writes can still live in the sidecars, so a main-file-only copy reads stale.
        foreach ($SidecarSuffix in '-wal', '-shm')
        {
            if (Test-Path -LiteralPath "$StatePath$SidecarSuffix")
            {
                Copy-Item -LiteralPath "$StatePath$SidecarSuffix" -Destination "$TempCopy$SidecarSuffix" -Force
            }
        }

        $ReadOnly = 1

        if ([VSCodeCouncil.SqliteCacheV1]::Open([System.Text.Encoding]::UTF8.GetBytes("$TempCopy`0"), [ref]$Database, $ReadOnly, [IntPtr]::Zero) -ne 0)
        {
            return [PSCustomObject]@{ Succeeded = $false; Records = @() }
        }

        foreach ($Sql in @(
                "SELECT value FROM ItemTable WHERE key='chat.cachedLanguageModels.v2'",
                "SELECT value FROM ItemTable WHERE key='chat.cachedLanguageModels'"
            ))
        {
            try
            {
                if ([VSCodeCouncil.SqliteCacheV1]::Prepare($Database, [System.Text.Encoding]::UTF8.GetBytes("$Sql`0"), -1, [ref]$Statement, [IntPtr]::Zero) -ne 0)
                {
                    $OperationalFailure = $true
                    continue
                }

                $StepResult = [VSCodeCouncil.SqliteCacheV1]::Step($Statement)

                if ($StepResult -ne $SqliteRow -and $StepResult -ne $SqliteDone)
                {
                    $OperationalFailure = $true
                }

                if ($StepResult -eq $SqliteRow)
                {
                    # SQLite documents blob-then-bytes as the safe order; the reverse can force a type conversion.
                    $Blob = [VSCodeCouncil.SqliteCacheV1]::ColumnBlob($Statement, 0)
                    $Length = [VSCodeCouncil.SqliteCacheV1]::ColumnBytes($Statement, 0)
                    $MaximumCacheLength = 64 * 1024 * 1024

                    if ($Length -gt $MaximumCacheLength)
                    {
                        # Skipped rather than thrown, so the older cache key is still tried.
                        Write-Verbose "Skipping the VS Code model cache value because it is implausibly large ($Length bytes)."
                        $Length = 0
                    }

                    if ($Length -gt 0 -and $Blob -ne [IntPtr]::Zero)
                    {
                        $Buffer = New-Object byte[] $Length
                        [System.Runtime.InteropServices.Marshal]::Copy($Blob, $Buffer, 0, $Length)

                        try
                        {
                            $ParsedRecords = @(ConvertFrom-ModelCacheJson -Json ([System.Text.Encoding]::UTF8.GetString($Buffer)))
                        }
                        catch
                        {
                            Write-Verbose "Skipping malformed JSON from VS Code model cache key in $StatePath. $($_.Exception.Message)"
                            $OperationalFailure = $true
                            continue
                        }

                        $Records = New-Object System.Collections.Generic.List[object]
                        $SeenNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

                        foreach ($Record in $ParsedRecords)
                        {
                            if ((Get-PropertyValue -InputObject $Record -Name 'identifier') -notlike 'copilot/*')
                            {
                                continue
                            }

                            $Metadata = Get-PropertyValue -InputObject $Record -Name 'metadata'

                            if ((Get-PropertyValue -InputObject $Metadata -Name 'isUserSelectable') -ne $true)
                            {
                                continue
                            }

                            $Capabilities = Get-PropertyValue -InputObject $Metadata -Name 'capabilities'

                            if ((Get-PropertyValue -InputObject $Capabilities -Name 'agentMode') -ne $true)
                            {
                                continue
                            }

                            $Name = [string](Get-PropertyValue -InputObject $Metadata -Name 'name')

                            if ((Test-ModelName -Name $Name) -and $SeenNames.Add($Name))
                            {
                                # VS Code publishes powerful, versatile, or lightweight per model. That beats
                                # inferring size from the name, which carries no signal for names like Luna.
                                $Records.Add([PSCustomObject]@{
                                        Name = $Name
                                        Category = [string](Get-PropertyValue -InputObject $Metadata -Name 'category')
                                    })
                            }
                        }

                        if ($Records.Count -gt 0)
                        {
                            return [PSCustomObject]@{ Succeeded = $true; Records = @($Records | Sort-Object -Property 'Name') }
                        }
                    }
                }
            }
            finally
            {
                if ($Statement -ne [IntPtr]::Zero)
                {
                    [void][VSCodeCouncil.SqliteCacheV1]::Release($Statement)
                    $Statement = [IntPtr]::Zero
                }
            }
        }
    }
    catch
    {
        Write-Verbose "Could not read models from $StatePath. $($_.Exception.Message)"

        return [PSCustomObject]@{ Succeeded = $false; Records = @() }
    }
    finally
    {
        if ($Statement -ne [IntPtr]::Zero)
        {
            [void][VSCodeCouncil.SqliteCacheV1]::Release($Statement)
        }

        if ($Database -ne [IntPtr]::Zero)
        {
            [void][VSCodeCouncil.SqliteCacheV1]::Close($Database)
        }

        Remove-Item -LiteralPath $TempCopy -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$TempCopy-wal" -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$TempCopy-shm" -Force -ErrorAction SilentlyContinue
    }

    return [PSCustomObject]@{ Succeeded = (-not $OperationalFailure); Records = @() }
}

# Tries the stable VS Code state database first, then Insiders, and returns the first one that
# yields any models. Returns an empty array when neither is readable, which sends the caller to
# the built-in fallback catalog.
function Get-VSCodeModelCatalog
{
    if ([string]::IsNullOrWhiteSpace($env:APPDATA) -or -not (Initialize-SqliteInterop))
    {
        return @()
    }

    $StatePaths = @(
        (Join-Path -Path $env:APPDATA -ChildPath 'Code\User\globalStorage\state.vscdb'),
        (Join-Path -Path $env:APPDATA -ChildPath 'Code - Insiders\User\globalStorage\state.vscdb')
    )

    foreach ($StatePath in $StatePaths)
    {
        if (-not (Test-Path -LiteralPath $StatePath))
        {
            continue
        }

        $MaximumAttempts = 2

        for ($Attempt = 1; $Attempt -le $MaximumAttempts; $Attempt++)
        {
            $Result = Get-CachedModelRecord -StatePath $StatePath

            if ($Result.Succeeded)
            {
                if ($Result.Records.Count -gt 0)
                {
                    return $Result.Records
                }

                # The snapshot was readable and held nothing usable, so a second copy cannot help.
                break
            }

            if ($Attempt -lt $MaximumAttempts)
            {
                Write-Console 'The first VS Code model-cache snapshot was unreadable. Retrying with a fresh snapshot.' -Level 'Detail'
            }
        }
    }

    return @()
}

#endregion

#region 7. Previous installation detection

# Recovers the models and coordinator model from an installation already on disk, so a re-run can
# offer to reuse them. Returns $null when nothing usable is found.
#
# The installed coordinator agent is the source of truth rather than a separate state file, which
# means the offer always reflects what is really installed and there is no extra file to go stale.
function Get-PreviousCouncilConfiguration
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $AgentDirectory,

        [Parameter(Mandatory = $true)]
        [string]
        $CoordinatorFileName
    )

    $CoordinatorPath = Join-Path -Path $AgentDirectory -ChildPath $CoordinatorFileName

    if (-not (Test-Path -LiteralPath $CoordinatorPath))
    {
        return $null
    }

    try
    {
        $Lines = @((Read-Utf8File -Path $CoordinatorPath) -split '\r?\n')
    }
    catch
    {
        Write-Verbose "Could not read the previously installed coordinator agent: $($_.Exception.Message)"
        return $null
    }

    $PreviousCoordinatorModel = $null
    $SeenModels = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $PreviousModels = New-Object System.Collections.Generic.List[string]
    $FrontMatterRoster = $null

    # Only the leading delimited block is front matter. Scanning the whole file would let any line in
    # the prompt body, which is workspace-controlled text, impersonate a roster declaration. An
    # unterminated block is not front matter at all, or the body would be trusted again.
    $FrontMatterLines = New-Object System.Collections.Generic.List[string]

    if ($Lines.Count -gt 0 -and $Lines[0].Trim() -eq '---')
    {
        for ($Index = 1; $Index -lt $Lines.Count; $Index++)
        {
            if ($Lines[$Index].Trim() -eq '---')
            {
                break
            }

            $FrontMatterLines.Add($Lines[$Index])
        }

        if ($Index -ge $Lines.Count)
        {
            $FrontMatterLines.Clear()
        }
    }

    foreach ($Line in $FrontMatterLines)
    {
        if ($null -eq $PreviousCoordinatorModel -and $Line -match '^model:\s*"(?<model>[^"]+)"\s*$')
        {
            $PreviousCoordinatorModel = $Matches['model'].Trim()
            continue
        }

        if ($null -eq $FrontMatterRoster -and $Line -match '^agents:\s*\[(?<agents>.*)\]\s*$')
        {
            $FrontMatterRoster = $Matches['agents']
        }
    }

    # The front-matter roster is machine-readable and is asserted at install time, so it is preferred
    # over the prose line, which changes whenever the coordinator prompt is reworded.
    if ($null -ne $FrontMatterRoster)
    {
        foreach ($Entry in ($FrontMatterRoster -split ','))
        {
            if ($Entry.Trim().Trim("'") -match '^(?<model>.+)\sExpert$')
            {
                $Candidate = $Matches['model'].Trim()

                if ((Test-ModelName -Name $Candidate) -and $SeenModels.Add($Candidate))
                {
                    $PreviousModels.Add($Candidate)
                }
            }
        }
    }

    if ($PreviousModels.Count -lt 1)
    {
        # Matches the roster line this installer writes: "- <Model> Expert running <Model>, primary lens <Lens>".
        foreach ($Line in $Lines)
        {
            if ($Line -match '^-\s.+\sExpert\srunning\s(?<model>[^,]+),\sprimary\slens\s.+$')
            {
                $Candidate = $Matches['model'].Trim()

                if ((Test-ModelName -Name $Candidate) -and $SeenModels.Add($Candidate))
                {
                    $PreviousModels.Add($Candidate)
                }
            }
        }
    }

    if ($PreviousModels.Count -lt 1)
    {
        return $null
    }

    if (-not (Test-ModelName -Name "$PreviousCoordinatorModel"))
    {
        $PreviousCoordinatorModel = $PreviousModels[0]
    }

    return [PSCustomObject]@{
        Models = $PreviousModels.ToArray()
        CoordinatorModel = $PreviousCoordinatorModel
        Path = $CoordinatorPath
    }
}

#endregion

#region 8. Model recommendation heuristic
#
# The goal of this section is one model per vendor. A peer review is only independent across
# training lineages, so two models from the same family would confirm each other's blind spots
# rather than challenge them. Everything below serves that single rule.

# Maps a model name to the vendor that trained it. The returned string is only ever used as a
# grouping key, so its exact value does not matter as long as it is stable.
function Get-ModelFamily
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    switch -Regex ($Name)
    {
        '(?i)^claude' { return 'Anthropic' }
        '(?i)^gemini' { return 'Google' }
        '(?i)^(gpt|o\d|codex)' { return 'OpenAI' }
        '(?i)^grok' { return 'xAI' }
        '(?i)^(mai|phi)' { return 'Microsoft' }
        '(?i)^(llama|mistral|deepseek|qwen)' { return 'OpenWeight' }
    }

    # A vendor this script has never seen still needs a stable family key, or every one of its models
    # would count as a separate vendor and the one-per-vendor rule would quietly stop holding.
    $Leading = [regex]::Match($Name, '^[A-Za-z]+')

    if ($Leading.Success)
    {
        return "Other:$($Leading.Value.ToLowerInvariant())"
    }

    return "Other:$Name"
}

# Scores how suitable a model is for an expert seat:
#   3  full size, prefer these
#   2  mid size, acceptable
#   0  reduced size, never recommend
#
# Prefers the category VS Code publishes over anything inferred from the name, because a name
# like "GPT-5.6 Luna" carries no size hint at all and guessing gets it wrong.
function Get-ModelTierWeight
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string]
        $Category
    )

    # VS Code publishes a size category per model, which is authoritative. The name-based rules below
    # are only a fallback for a supplied catalog or a cache that predates the field.
    if (-not [string]::IsNullOrWhiteSpace($Category))
    {
        switch -Regex ($Category)
        {
            '(?i)^powerful$' { return 3 }
            '(?i)^versatile$' { return 2 }
            '(?i)^lightweight$' { return 0 }
        }
    }

    # A reduced-size model serves poorly as an expert and worse as that expert's peer reviewer.
    if ($Name -match '(?i)(^|[\s\-])(mini|flash|haiku|nano|lite|small|turbo|instant)([\s\-]|$)')
    {
        return 0
    }

    if ($Name -match '(?i)(^|[\s\-])(opus|ultra|max|heavy)([\s\-]|$)')
    {
        return 3
    }

    if ($Name -match '(?i)(^|[\s\-])(pro|sonnet)([\s\-]|$)')
    {
        return 2
    }

    return 1
}

# Pulls the first number out of a model name, so "Claude Opus 4.8" becomes 4.8 and "Claude Opus 5"
# becomes 5.0. Only ever compared against another model from the same vendor, since numbering
# schemes are unrelated across vendors.
function Get-ModelVersion
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Name
    )

    $Match = [regex]::Match($Name, '(\d+)(?:\.(\d+))?')

    if (-not $Match.Success)
    {
        return [version]::new(0, 0)
    }

    $Major = 0

    if (-not [int]::TryParse($Match.Groups[1].Value, [ref]$Major))
    {
        return [version]::new(0, 0)
    }

    $Minor = 0

    if ($Match.Groups[2].Success -and -not [int]::TryParse($Match.Groups[2].Value, [ref]$Minor))
    {
        return [version]::new(0, 0)
    }

    return [version]::new($Major, $Minor)
}

# Picks up to MaximumCount models from the supplied catalog, in the order they should be assigned
# to lenses. Returns an empty array when the catalog contains nothing worth recommending.
#
# The algorithm, in order:
#   1. Discard the Auto router and every reduced-size model.
#   2. Rank what is left by tier, then vendor, then version within that vendor.
#   3. Take the best model from each vendor first, which is the whole point of the exercise.
#   4. Only once vendors run out, fill the remaining slots, preferring a coding specialist over
#      another general model from a vendor that is already represented.
function Get-RecommendedModelSet
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]
        $Catalog,

        [Parameter(Mandatory = $true)]
        [int]
        $MaximumCount,

        [Parameter()]
        [AllowNull()]
        [hashtable]
        $CategoryMap
    )

    if ($null -eq $CategoryMap)
    {
        $CategoryMap = @{}
    }

    $SeenCatalogNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $Candidates = @(
        $Catalog |
            Where-Object { (Test-ModelName -Name $_) -and $_ -notmatch '(?i)^auto$' -and $SeenCatalogNames.Add($_) } |
            ForEach-Object {
                $Category = ''

                if ($CategoryMap.ContainsKey($_))
                {
                    $Category = [string]$CategoryMap[$_]
                }

                [PSCustomObject]@{
                    Name = $_
                    Family = Get-ModelFamily -Name $_
                    Tier = Get-ModelTierWeight -Name $_ -Category $Category
                    Version = Get-ModelVersion -Name $_
                    Specialist = [bool]($_ -match '(?i)codex|(^|[\s\-])code([\s\-]|$)')
                }
            } |
            Where-Object { $_.Tier -gt 0 }
    )

    if ($Candidates.Count -lt 1)
    {
        return @()
    }

    # A version number only means something inside one vendor, so families are ordered by the tier of
    # their best model and then by name. Nothing here claims one vendor outranks another.
    $FamilyOrder = @($Candidates |
            Group-Object -Property 'Family' |
            Sort-Object -Property `
            @{ Expression = { ($_.Group | Measure-Object -Property 'Tier' -Maximum).Maximum }; Descending = $true },
        @{ Expression = 'Name'; Descending = $false })

    $FamilyRank = @{}

    for ($Index = 0; $Index -lt $FamilyOrder.Count; $Index++)
    {
        $FamilyRank[$FamilyOrder[$Index].Name] = $Index
    }

    $Ranked = @($Candidates | Sort-Object -Property `
        @{ Expression = 'Tier'; Descending = $true },
        @{ Expression = { $FamilyRank[$_.Family] }; Descending = $false },
        @{ Expression = 'Version'; Descending = $true },
        @{ Expression = 'Name'; Descending = $false })

    $Chosen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $UsedFamilies = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    # One model per vendor first. A peer review is only independent across training lineages, so two
    # models from the same family would review each other's blind spots rather than challenge them.
    foreach ($Candidate in $Ranked)
    {
        if ($Chosen.Count -ge $MaximumCount)
        {
            break
        }

        if ($UsedFamilies.Add($Candidate.Family))
        {
            [void]$Chosen.Add($Candidate.Name)
        }
    }

    # Then fill from what is left, preferring a coding specialist over another general sibling.
    if ($Chosen.Count -lt $MaximumCount)
    {
        $Remaining = @($Ranked |
                Where-Object { -not $Chosen.Contains($_.Name) } |
                Sort-Object -Property `
                @{ Expression = { -not $_.Specialist } },
            @{ Expression = 'Tier'; Descending = $true },
            @{ Expression = 'Version'; Descending = $true },
            @{ Expression = 'Name'; Descending = $false })

        foreach ($Candidate in $Remaining)
        {
            if ($Chosen.Count -ge $MaximumCount)
            {
                break
            }

            [void]$Chosen.Add($Candidate.Name)
        }
    }

    # Emit in rank order, not selection order, so the strongest model lands in the first lens.
    return @($Ranked | Where-Object { $Chosen.Contains($_.Name) } | ForEach-Object { $_.Name })
}

#endregion

#region 9. Interactive prompts

# Shows the model picker and loops until the user confirms a usable selection.
#
# Accepts menu numbers, typed model names, C for a custom name, or R for the recommended set.
# The R shortcut rewrites the response into the normal comma-separated form rather than taking a
# separate code path, so the recommended names get exactly the same validation as typed ones.
function Select-ModelList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]]
        $Catalog,

        [Parameter(Mandatory = $true)]
        [int]
        $MaximumCount,

        [Parameter(Mandatory = $true)]
        [bool]
        $Discovered,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]
        $Recommended,

        [Parameter(Mandatory = $true)]
        [string[]]
        $LensTitles,

        [Parameter(Mandatory = $true)]
        [string]
        $RecommendationDate
    )

    $MaximumAttempts = 25
    $Attempt = 0

    while ($true)
    {
        $Attempt++

        if ($Attempt -gt $MaximumAttempts)
        {
            throw 'No usable model selection was entered. Re-run with -Models, or with -NonInteractive to accept the defaults.'
        }

        Write-Host ''

        if ($Discovered)
        {
            Write-Host 'Models available to your GitHub Copilot account:'
        }
        else
        {
            Write-Host 'Suggested models (names must match the Visual Studio Code model picker):'
        }

        for ($Index = 0; $Index -lt $Catalog.Count; $Index++)
        {
            $Marker = $(if ($Recommended -contains $Catalog[$Index]) { '*' } else { ' ' })
            Write-Host ('  {0} [{1}] {2}' -f $Marker, ($Index + 1), $Catalog[$Index])
        }

        Write-Host '    [C] Enter a custom model name'

        if ($Recommended.Count -gt 0)
        {
            Write-Host '    [R] Use the recommended set marked with *'
            Write-Host ''
            Write-Host ('Recommended as of {0}: {1}' -f $RecommendationDate, ($Recommended -join ', '))
            Write-Host 'Detected from this catalog by taking the newest model per vendor that VS Code publishes as'
            Write-Host 'powerful or versatile, because a peer review is only independent across vendors.'
        }

        Write-Host ''
        Write-Host ('Choose 1 to {0} models, separated by commas. Example: 1,4' -f $MaximumCount)
        Write-Host 'You may also type a model name directly.'
        Write-Host 'Order matters. Each position is assigned a different expert lens.'

        $Response = Read-Host -Prompt 'Models'

        if ([string]::IsNullOrWhiteSpace($Response))
        {
            Write-Host 'No selection was entered.' -ForegroundColor Yellow
            continue
        }

        if ($Recommended.Count -gt 0 -and $Response.Trim() -match '^[Rr]$')
        {
            # Re-enters the normal token path so the recommended names get the same validation.
            $Response = $Recommended -join ','
        }

        $Selected = New-Object System.Collections.Generic.List[string]
        $HasError = $false

        foreach ($Token in ($Response -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }))
        {
            if ($Token -match '^\d+$')
            {
                $Position = 0

                if (-not [int]::TryParse($Token, [ref]$Position) -or $Position -lt 1 -or $Position -gt $Catalog.Count)
                {
                    Write-Host ("'{0}' is not a valid menu number." -f $Token) -ForegroundColor Yellow
                    $HasError = $true
                    break
                }

                $Selected.Add($Catalog[$Position - 1])
            }
            elseif ($Token -match '^[Cc]$')
            {
                $Custom = "$(Read-Host -Prompt 'Custom model name')".Trim()

                if (-not (Test-ModelName -Name $Custom))
                {
                    Write-Host ("'{0}' is not a usable model name." -f $Custom) -ForegroundColor Yellow
                    $HasError = $true
                    break
                }

                $Selected.Add($Custom)
            }
            elseif (Test-ModelName -Name $Token)
            {
                # VS Code matches model names case-sensitively, so prefer the catalog spelling.
                $CatalogMatch = @($Catalog | Where-Object { $_ -eq $Token })

                if ($CatalogMatch.Count -gt 0)
                {
                    $Selected.Add($CatalogMatch[0])
                }
                else
                {
                    $Selected.Add($Token)
                }
            }
            else
            {
                Write-Host ("'{0}' is not a usable model name." -f $Token) -ForegroundColor Yellow
                $HasError = $true
                break
            }
        }

        if ($HasError)
        {
            continue
        }

        # Case-insensitive, so picking the same model twice under different spellings collapses to one.
        $SeenSelections = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $Unique = @($Selected | Where-Object { $SeenSelections.Add($_) })

        if ($Unique.Count -lt 1)
        {
            Write-Host 'Select at least one model.' -ForegroundColor Yellow
            continue
        }

        if ($Unique.Count -gt $MaximumCount)
        {
            Write-Host ('Select no more than {0} models.' -f $MaximumCount) -ForegroundColor Yellow
            continue
        }

        Write-Host ''
        Write-Host 'Selected models:'

        for ($Index = 0; $Index -lt $Unique.Count; $Index++)
        {
            Write-Host ('  {0} - lens: {1}' -f $Unique[$Index], $LensTitles[$Index % $LensTitles.Count])
        }

        $Confirm = "$(Read-Host -Prompt 'Continue with these models? [Y/n]')".Trim()

        if ([string]::IsNullOrWhiteSpace($Confirm) -or $Confirm -match '^[Yy]')
        {
            return $Unique
        }
    }
}

# Asks which of the already-chosen models should run the coordinator. Returns immediately when
# only one model is configured, since there is nothing to choose.
function Select-CoordinatorModel
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string[]]
        $ModelList
    )

    if ($ModelList.Count -eq 1)
    {
        return $ModelList[0]
    }

    while ($true)
    {
        Write-Host ''
        Write-Host 'Which model should run the coordinator?'

        for ($Index = 0; $Index -lt $ModelList.Count; $Index++)
        {
            Write-Host ('  [{0}] {1}' -f ($Index + 1), $ModelList[$Index])
        }

        Write-Host ''
        $Response = "$(Read-Host -Prompt ('Coordinator model [default 1 - {0}]' -f $ModelList[0]))".Trim()

        if ([string]::IsNullOrWhiteSpace($Response))
        {
            return $ModelList[0]
        }

        if ($Response -match '^\d+$')
        {
            $Position = 0

            if ([int]::TryParse($Response, [ref]$Position) -and $Position -ge 1 -and $Position -le $ModelList.Count)
            {
                return $ModelList[$Position - 1]
            }
        }

        Write-Host 'Enter one of the listed numbers.' -ForegroundColor Yellow
    }
}

#endregion

#region 10. VS Code settings file

# Resolves which settings.json to edit, preferring an explicit path, then stable VS Code, then
# Insiders. Falls back to the stable path so a missing file gets created in the expected place.
function Get-VSCodeUserSettingsPath
{
    param
    (
        [Parameter()]
        [string]
        $ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath))
    {
        # Resolves against the PowerShell location rather than the process working directory, which can differ after Set-Location.
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExplicitPath)
    }

    if ([string]::IsNullOrWhiteSpace($env:APPDATA))
    {
        throw 'APPDATA is not available. Specify -VSCodeSettingsPath explicitly.'
    }

    $StablePath = Join-Path -Path $env:APPDATA -ChildPath 'Code\User\settings.json'
    $InsidersPath = Join-Path -Path $env:APPDATA -ChildPath 'Code - Insiders\User\settings.json'

    if (Test-Path -LiteralPath $StablePath)
    {
        return $StablePath
    }

    if (Test-Path -LiteralPath $InsidersPath)
    {
        return $InsidersPath
    }

    return $StablePath
}

# Replaces every comment with spaces while leaving string literals and the total length alone.
#
# Searching the masked copy means a setting that appears inside a comment is never mistaken for a
# real one, and because the length is unchanged, any index found here is valid in the original.
function ConvertTo-CommentMaskedJson
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    # Blanks comments while preserving length, so offsets still map onto the original text.
    return [regex]::Replace(
        $Text,
        '(?s)("(?:\\.|[^"\\])*")|//[^\r\n]*|/\*.*?\*/',
        {
            param ($Match)

            if ($Match.Groups[1].Success)
            {
                return $Match.Value
            }

            return ($Match.Value -replace '[^\r\n]', ' ')
        })
}

# Parses JSON with comments, the dialect VS Code settings files actually use. Comments and
# trailing commas are both legal there and both rejected by ConvertFrom-Json.
function ConvertFrom-JsoncText
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Text
    )

    # ConvertFrom-Json rejects comments and trailing commas, both of which are legal in a VS Code settings file.
    $Masked = ConvertTo-CommentMaskedJson -Text $Text
    $StrictJson = [regex]::Replace(
        $Masked,
        '("(?:\\.|[^"\\])*")|,(?=\s*[}\]])',
        {
            param ($Match)

            if ($Match.Groups[1].Success) { $Match.Value } else { '' }
        })

    return ($StrictJson | ConvertFrom-Json)
}

# Locates a property value on the root JSON object without mistaking comments, strings, nested
# objects, or arrays for the setting. The returned offsets map directly onto the original text.
function Get-RootJsonPropertyToken
{
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Text,

        [Parameter(Mandatory = $true)]
        [string]
        $PropertyName
    )

    $Masked = ConvertTo-CommentMaskedJson -Text $Text
    $Tokens = [regex]::Matches($Masked, '"(?:\\.|[^"\\])*"|[{}\[\]:,]|true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?')
    $ObjectDepth = 0
    $ArrayDepth = 0
    $RootOpenBraceIndex = -1
    $ValueMatches = New-Object System.Collections.Generic.List[object]

    for ($Index = 0; $Index -lt $Tokens.Count; $Index++)
    {
        $Token = $Tokens[$Index]

        switch ($Token.Value)
        {
            '{'
            {
                if ($RootOpenBraceIndex -lt 0 -and $ObjectDepth -eq 0 -and $ArrayDepth -eq 0)
                {
                    $RootOpenBraceIndex = $Token.Index
                }

                $ObjectDepth++
            }
            '}'
            {
                $ObjectDepth--
            }
            '['
            {
                $ArrayDepth++
            }
            ']'
            {
                $ArrayDepth--
            }
        }

        # No continue above: inside a switch it would only leave the switch, not this loop. The
        # structural tokens fall through to the quote test below, which rejects them anyway.

        if ($ObjectDepth -ne 1 -or $ArrayDepth -ne 0 -or -not $Token.Value.StartsWith('"'))
        {
            continue
        }

        try
        {
            $DecodedName = [string]($Token.Value | ConvertFrom-Json)
        }
        catch
        {
            continue
        }

        if ($DecodedName -cne $PropertyName -or $Index + 2 -ge $Tokens.Count -or $Tokens[$Index + 1].Value -ne ':')
        {
            continue
        }

        $ValueToken = $Tokens[$Index + 2]
        $ValueMatches.Add([PSCustomObject]@{
                Index = $ValueToken.Index
                Length = $ValueToken.Length
                Value = $ValueToken.Value
            })
    }

    return [PSCustomObject]@{
        RootOpenBraceIndex = $RootOpenBraceIndex
        ValueMatches = $ValueMatches.ToArray()
    }
}

# Turns on nested subagents in the user's settings.json, which the council needs so an expert can
# consult a reviewer.
#
# This edits a file the script does not own, so it is deliberately conservative:
#   - the existing value is patched in place rather than the object being rebuilt, which would
#     throw away the user's comments and formatting
#   - the result is parsed and checked before it is written, and again after
#   - a pre-existing non-boolean value is a hard error rather than a silent second key
#   - the file is backed up first
function Set-VSCodeNestedSubagentsSetting
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $SettingsPath,

        [Parameter(Mandatory = $true)]
        [string]
        $BackupDirectory,

        # Records what actually reached disk. A return value cannot do this, because the throw paths
        # that rollback exists for never return one.
        [Parameter(Mandatory = $false)]
        [hashtable]
        $WriteState
    )

    $SettingsDirectory = Split-Path -Path $SettingsPath -Parent

    if (-not (Test-Path -LiteralPath $SettingsDirectory))
    {
        New-Item -Path $SettingsDirectory -ItemType Directory -Force | Out-Null
    }

    $SettingsExisted = Test-Path -LiteralPath $SettingsPath

    # The raw text is kept apart from the parsed text, because an empty or whitespace-only file is
    # treated as {} but still has to compare equal to itself in the pre-write concurrency check.
    $OriginalContent = if ($SettingsExisted) { Read-Utf8File -Path $SettingsPath } else { '' }
    $Content = $OriginalContent

    if ([string]::IsNullOrWhiteSpace($Content))
    {
        $Content = '{}'
    }

    $SettingName = 'chat.subagents.allowInvocationsFromSubagents'

    # Matched to the file's existing style so an inserted line does not create mixed line endings.
    $NewLine = [Environment]::NewLine

    if ($Content -match "`r`n")
    {
        $NewLine = "`r`n"
    }
    elseif ($Content.Contains("`n"))
    {
        $NewLine = "`n"
    }

    $PropertyToken = Get-RootJsonPropertyToken -Text $Content -PropertyName $SettingName
    $SettingMatches = @($PropertyToken.ValueMatches)

    if ($SettingMatches.Count -gt 1)
    {
        throw "$SettingName appears more than once on the root object in $SettingsPath. Remove the duplicate, then re-run."
    }

    if ($SettingMatches.Count -eq 1)
    {
        $SettingMatch = $SettingMatches[0]

        if ($SettingMatch.Value -eq 'true')
        {
            # Nothing is written here, so a parse failure is reported rather than thrown: the value is
            # already correct, but VS Code will ignore the whole file if it cannot parse it.
            try
            {
                $null = ConvertFrom-JsoncText -Text $Content
            }
            catch
            {
                Write-Console "VS Code settings file could not be parsed, so VS Code may ignore it and leave nested subagents inactive: $SettingsPath" -Level 'Warning'
            }

            Write-Console "VS Code setting is already enabled: $SettingName = true"
            Write-Console "VS Code settings file: $SettingsPath"
            return $false
        }

        if ($SettingMatch.Value -ne 'false')
        {
            throw "$SettingName already exists in $SettingsPath with a value that is not true or false. Correct it by hand, then re-run."
        }

        $UpdatedContent = $Content.Remove($SettingMatch.Index, $SettingMatch.Length).Insert($SettingMatch.Index, 'true')
    }
    else
    {
        $OpenBraceIndex = $PropertyToken.RootOpenBraceIndex

        if ($OpenBraceIndex -lt 0)
        {
            throw "VS Code settings file does not appear to contain a root JSON object: $SettingsPath"
        }

        # Inserting always beats rebuilding the object, because rebuilding would discard the user's comments.
        # A root object holding nothing but whitespace or comments must not gain a trailing comma.
        $Separator = ''
        $Masked = ConvertTo-CommentMaskedJson -Text $Content

        if ($Masked.Substring($OpenBraceIndex + 1) -match '[^\s}]')
        {
            $Separator = ','
        }

        $TextAfterOpenBrace = $Content.Substring($OpenBraceIndex + 1)
        $NeedsTrailingNewLine = -not ($TextAfterOpenBrace.StartsWith("`r`n") -or $TextAfterOpenBrace.StartsWith("`n"))
        $SettingLine = $NewLine + "  `"$SettingName`": true$Separator" + $(if ($NeedsTrailingNewLine) { $NewLine } else { '' })
        $UpdatedContent = $Content.Insert($OpenBraceIndex + 1, $SettingLine)
    }

    # Validated before the write, so a bad edit can never reach the user's real settings file.
    try
    {
        $ProposedSettings = ConvertFrom-JsoncText -Text $UpdatedContent
    }
    catch
    {
        throw "Updating $SettingsPath would produce invalid JSON, so nothing was written. $($_.Exception.Message)"
    }

    if ((Get-PropertyValue -InputObject $ProposedSettings -Name $SettingName) -ne $true)
    {
        throw "Refusing to write $SettingsPath because the update did not set $SettingName to true."
    }

    if ($SettingsExisted)
    {
        $CurrentContent = Read-Utf8File -Path $SettingsPath

        if ($CurrentContent -cne $OriginalContent)
        {
            throw "VS Code settings changed while the installer was preparing its update. Nothing was written: $SettingsPath"
        }

        Backup-ExistingFile -Path $SettingsPath -BackupDirectory $BackupDirectory
    }

    if ($null -ne $WriteState)
    {
        $WriteState['Attempted'] = $true
    }

    # PreserveLineEndings keeps the user's existing CRLF or LF style instead of rewriting the whole file.
    Write-Utf8File -Path $SettingsPath -Content $UpdatedContent -PreserveLineEndings

    if (-not $SettingsExisted)
    {
        Write-Console "Created VS Code settings file: $SettingsPath"
    }

    $WrittenContent = Read-Utf8File -Path $SettingsPath

    if ($null -ne $WriteState)
    {
        $WriteState['WrittenContent'] = $WrittenContent
    }

    try
    {
        $WrittenSettings = ConvertFrom-JsoncText -Text $WrittenContent
    }
    catch
    {
        throw "Updating $SettingsPath produced invalid JSON. A backup was written to $BackupDirectory. $($_.Exception.Message)"
    }

    if ((Get-PropertyValue -InputObject $WrittenSettings -Name $SettingName) -ne $true)
    {
        throw "Failed to verify $SettingName=true in $SettingsPath. A backup was written to $BackupDirectory"
    }

    Write-Console "Enabled VS Code setting: $SettingName = true"
    Write-Console "VS Code settings file: $SettingsPath"

    return $true
}

#endregion

#region 11. Agent file content
#
# The three New-*AgentContent functions below return the complete text of an agent file: YAML
# front matter followed by the instructions that model will receive as its system prompt.
#
# They use expandable here-strings, so any literal $ or backtick in the prompt text has to be
# escaped. Forgetting that is the most likely way to break this section.

# Builds the YAML header every agent file starts with.
#
# user-invocable false hides a worker from the picker, while disable-model-invocation false leaves
# it eligible for the explicit subagent allowlists generated below. The selectable coordinator uses
# disable-model-invocation true so another agent cannot recruit the whole council as one subagent.
function New-AgentFrontMatter
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Name,

        [Parameter(Mandatory = $true)]
        [string]
        $Description,

        [Parameter(Mandatory = $true)]
        [string]
        $Model,

        [Parameter(Mandatory = $true)]
        [bool]
        $UserInvocable,

        [Parameter(Mandatory = $true)]
        [bool]
        $DisableModelInvocation,

        [Parameter(Mandatory = $true)]
        [string[]]
        $Tools,

        [Parameter()]
        [string[]]
        $Agents
    )

    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add('---')
    $Lines.Add("name: $Name")
    $Lines.Add("description: $Description")
    $Lines.Add("model: `"$Model`"")
    $Lines.Add('target: vscode')
    $Lines.Add("user-invocable: $(if ($UserInvocable) { 'true' } else { 'false' })")
    $Lines.Add("disable-model-invocation: $(if ($DisableModelInvocation) { 'true' } else { 'false' })")
    $Lines.Add("tools: [$(($Tools | ForEach-Object { "'$_'" }) -join ', ')]")

    if ($null -ne $Agents -and $Agents.Count -gt 0)
    {
        $Lines.Add("agents: [$(($Agents | ForEach-Object { "'$_'" }) -join ', ')]")
    }

    $Lines.Add('---')

    return ($Lines -join "`n")
}

# Builds a leaf peer reviewer. Deliberately has no agent tool and no agents list, which is what
# physically caps nesting at two levels instead of relying on the model to restrain itself.
function New-ReviewerAgentContent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $AgentName,

        [Parameter(Mandatory = $true)]
        [string]
        $ModelName
    )

    $FrontMatter = New-AgentFrontMatter `
        -Name $AgentName `
        -Description "Leaf peer reviewer running $ModelName. Challenges an expert conclusion and cannot invoke subagents." `
        -Model $ModelName `
        -UserInvocable $false `
        -DisableModelInvocation $false `
        -Tools $ReviewerAgentTools

    return @"
$FrontMatter

# $AgentName

You are a leaf peer-review agent running $ModelName.

An expert agent invoked you for one independent challenge. You have no subagent tool. Do not attempt to delegate.

## Your job

Attack the supplied conclusion where it is weakest, then state what you would conclude instead.

Evaluate:

- factual and technical correctness
- unsupported or unverified assumptions
- edge cases and failure paths
- regression, concurrency, and ordering risk
- security exposure and unsafe defaults
- architecture and maintainability consequences
- feasibility and compatibility
- whether a materially simpler solution exists

Do not disagree to create conflict. If the conclusion is correct, say so, say why, and name the one risk that remains.

## Evidence order

$EvidenceHierarchyText

Do not invent evidence. Label any claim you could not verify as unverified.

## Output

The expert quotes you to the user, so write for that audience. Open with this exact block:

    STANCE: Strong agree | Agree | Disagree | Strong disagree
    CONFIDENCE: High | Medium | Low
    KEY EVIDENCE: the file, test, or observed behavior that decided it
    CHALLENGE: the single claim you are attacking, or None
    OPEN QUESTION: the risk that remains, or None

Then add at most five lines covering:

- what is correct
- what is wrong, with the correction
- what is missing

Write every line so it can be shown to the user unedited. Summarize, do not paste back the material you were given, and do not continue the conversation through another agent.
"@
}

# Builds one expert, bound to a single review lens and to a list of reviewers that never includes
# its own. The lens text is what stops five parallel experts from returning the same answer.
function New-ExpertAgentContent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $AgentName,

        [Parameter(Mandatory = $true)]
        [string]
        $ModelName,

        [Parameter(Mandatory = $true)]
        [string]
        $LensTitle,

        [Parameter(Mandatory = $true)]
        [string[]]
        $LensFocus,

        [Parameter(Mandatory = $true)]
        [string[]]
        $ReviewerNames,

        [Parameter(Mandatory = $true)]
        [string]
        $CoordinatorName,

        [Parameter(Mandatory = $true)]
        [bool]
        $CrossModelReview
    )

    $FrontMatter = New-AgentFrontMatter `
        -Name $AgentName `
        -Description "Engineering expert running $ModelName with a primary lens of $LensTitle. Hidden worker invoked by the $CoordinatorName." `
        -Model $ModelName `
        -UserInvocable $false `
        -DisableModelInvocation $false `
        -Tools $ExpertAgentTools `
        -Agents $ReviewerNames

    $FocusBlock = ($LensFocus | ForEach-Object { "- $_" }) -join "`n"
    $ReviewerBlock = ($ReviewerNames | ForEach-Object { "- $_" }) -join "`n"

    if ($CrossModelReview)
    {
        $ReviewerIntro = 'Each of these reviewers runs a different model than you do, so the critique is genuinely independent.'
        $RequiredTierLine = 'Tier 3 and Tier 5 use REQUIRED.'
    }
    else
    {
        $ReviewerIntro = 'Only one model is configured, so this reviewer runs the same model with a fresh context. Treat it as a blind-spot check, not as an independent model.'
        $RequiredTierLine = 'Tier 5 uses REQUIRED. The single-model Tier 3 fallback uses SKIP.'
    }

    return @"
$FrontMatter

# $AgentName

You are an engineering expert running $ModelName inside a multi-model council.

Your primary lens is $LensTitle.

## Primary lens

Prioritize:

$FocusBlock

Report anything materially wrong outside your lens in one line. Do not expand into another expert's lens.

## Method

1. Read the delegation brief. Do not redo work the coordinator already verified.
2. Narrate your progress. Before each significant search or tool call, state in one line what you are checking, for example "Scanning Get-VSCodeStatus for Windows-only path assumptions". Never work silently.
3. Gather only the evidence that can change your answer. Stop searching once you can act.
4. Form your own position before considering any other model.
5. Name your assumptions and your remaining uncertainty.
6. Identify the strongest competing alternative and why you rejected it.

## Controlled cross-model review

You may invoke at most ONE of the following reviewers, at most ONE time, for the entire assignment:

$ReviewerBlock

$ReviewerIntro

The coordinator must include exactly one directive block in your delegation brief:

    NESTED REVIEW: REQUIRED | AUTHORIZED | SKIP
    REVIEWER: one reviewer from the list above, or NONE
    TARGET: one concrete claim or assumption to challenge, or NONE

REQUIRED means you must form your own position, then invoke the named reviewer exactly once and ask it to attack the target. $RequiredTierLine

AUTHORIZED means you may invoke the named reviewer once, but only when at least one of these is true:

- your conclusion is high impact or hard to reverse
- a critical assumption is unverified and you cannot verify it with a tool
- security, data integrity, or shared behavior is at stake
- the evidence is thin or conflicting

SKIP means do not invoke a reviewer. If the directive is missing or malformed, treat it as SKIP and report that omission.

Never substitute a different reviewer or target without reporting why the named one is unavailable. A nested review roughly doubles the cost of your branch.

When you invoke a reviewer, supply:

- the assigned task and the definition of done
- your current conclusion
- the evidence you relied on
- your assumptions
- the exact claim you want attacked

Ask it to attack your strongest assumption, not to agree with you.

After it returns:

1. Accept the critique where evidence supports it.
2. Reject unsupported criticism and state why in one line.
3. Return your revised position.

Do not invoke a second reviewer. Do not invoke yourself. Do not attempt recursive debate.

## Evidence

$EvidenceHierarchyText

Confidence is not evidence. Model agreement is not evidence.

## Output

The coordinator publishes your position to the user, so write for that audience. Open with this exact block:

    STANCE: your position in one sentence
    CONFIDENCE: High | Medium | Low
    KEY EVIDENCE: the file, line, test, or observed behavior that decided it
    DISAGREES WITH: the expert or assumption you contradict, or None
    OPEN QUESTION: what stays unverified, or None

Then use at most eight lines for:

- the reasoning behind that stance, in plain language
- the strongest alternative you rejected, and why
- what you deliberately left out of scope

The eight-line limit is lifted only when the brief explicitly says this is a Tier 5 brainstorm and asks for an exhaustive answer. Then answer at whatever length the evidence justifies.

Only your final message reaches the coordinator, so the progress you narrated while working is not visible to anyone on its own. Carry it forward as a CHECKED line naming the files, symbols, or commands you actually examined, so the user can see what was and was not looked at.

If you used a reviewer, add a REVIEWER CHALLENGE line naming its strongest objection and whether it changed your stance. Report it even when it changed nothing, because the user is entitled to know the position was tested.

Write every line so it can be shown to the user unedited. Summarize your reasoning. Do not paste raw transcripts and do not expose private chain-of-thought.

Do not edit repository files unless the brief explicitly assigns you a file and your tools allow it.
"@
}

# Builds the coordinator, the only agent the user selects directly.
#
# Most of the body is spent talking the model out of over-delegating. Left alone, a model with
# five available experts will use all five on a question that needed none, so the tier rules,
# the escalation limits, and the explicit cost of each tier all exist to push it downward.
function New-CoordinatorAgentContent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $AgentName,

        [Parameter(Mandatory = $true)]
        [string]
        $ModelName,

        [Parameter(Mandatory = $true)]
        [object[]]
        $ExpertMap,

        [Parameter(Mandatory = $true)]
        [bool]
        $CrossModelReview
    )

    $ExpertNames = @($ExpertMap | ForEach-Object { $_.ExpertName })

    $FrontMatter = New-AgentFrontMatter `
        -Name $AgentName `
        -Description 'Adaptive multi-model engineering coordinator that automatically selects a direct answer, one expert, a dual council, an adversarial debate, or a full parallel team based on task complexity.' `
        -Model $ModelName `
        -UserInvocable $true `
        -DisableModelInvocation $true `
        -Tools $CoordinatorAgentTools `
        -Agents $ExpertNames

    $RosterBlock = ($ExpertMap | ForEach-Object {
            "- $($_.ExpertName) running $($_.ModelName), primary lens $($_.LensTitle)"
        }) -join "`n"

    $ReviewBlock = ($ExpertMap | ForEach-Object {
            "- $($_.ExpertName) may consult one of: $($_.ReviewerNames -join ', ')"
        }) -join "`n"

    $ExpertCount = $ExpertMap.Count
    $Tier5ExpertCost = if ($ExpertCount -eq 1) { 'one expert call' } else { "up to $ExpertCount parallel expert calls" }
    $Tier5ReviewerCost = if ($ExpertCount -eq 1) { 'one leaf-reviewer call' } else { "$ExpertCount leaf-reviewer calls" }

    if ($CrossModelReview)
    {
        $Tier2Body = @'
Use when:

- the task spans two lenses, and
- there is a real design or implementation choice to make, or the change touches shared code or public behavior

Invoke both experts in the same turn with distinct, non-overlapping scopes, then synthesize. Cost: two parallel expert calls.

Include NESTED REVIEW: SKIP in both delegation briefs.
'@

        $Tier3Note = @'
Run two experts on different models in parallel. Give both the same disputed claim and include a REQUIRED nested-review directive naming a different-model reviewer and the strongest assumption supporting that expert's position.
'@

        $Tier3Cost = 'Cost: two expert calls plus their nested reviews, so roughly four model invocations.'

        $Tier4Body = @"
Use ONLY when at least one of these is true:

- the user explicitly asked for the full team or a complete review
- the work spans several genuinely independent subsystems that need different lenses at once
- a difficult bug has already survived a Tier 1 or Tier 2 attempt

Breadth of files alone is not a Tier 4 trigger. A large but uniform change is Tier 1 or Tier 2.

Fan out one expert per configured model, each with its own lens and its own scope.

Nested review is off by default. Include NESTED REVIEW: SKIP for every branch unless that branch independently meets the Tier 3 conditions and no cheaper evidence can settle it. For a qualifying branch, include NESTED REVIEW: AUTHORIZED, name one configured reviewer, and name the exact target to challenge.

Cost: up to $ExpertCount parallel expert calls, plus at most one reviewer call for each explicitly authorized branch.
"@

        $NestedReviewRequiredLine = 'Use REQUIRED for both cross-model Tier 3 branches and every Tier 5 branch.'
        $NestedReviewSkipLine = 'Use SKIP for Tier 1, Tier 2, and all other Tier 4 branches.'
    }
    else
    {
        $Tier2Body = @'
Unavailable. Only one model is configured, so there is no second expert to run beside the first. Stay at Tier 1, and go to Tier 3 only when the task genuinely needs opposing framings.
'@

        $Tier3Note = @'
Only one model is configured, so a true cross-model debate is not possible. Run the single expert twice with opposing framings, once to defend the proposal and once to break it. Give both runs NESTED REVIEW: SKIP, then adjudicate the positions yourself.
'@

        $Tier3Cost = 'Cost: two sequential expert calls and no reviewer calls, so two model invocations.'

        $Tier4Body = @'
Unavailable. Only one model is configured, so a parallel team would be the same expert repeated against itself. Stay at Tier 1, or use Tier 3 when opposing framings are genuinely needed.
'@

        $NestedReviewRequiredLine = 'Use REQUIRED for every Tier 5 branch.'
        $NestedReviewSkipLine = 'Use SKIP for Tier 1 and for both runs of the single-model Tier 3 fallback.'
    }

    return @"
$FrontMatter

# $AgentName

You are the single entry point for multi-model engineering work.

You automatically select the cheapest strategy that can produce a correct, defensible answer. You do not run a fixed ceremony, and you do not spend model calls to look busy.

## Configured experts

$RosterBlock

## Controlled nested review

$ReviewBlock

Reviewers are leaf agents. They have no subagent tool, so nesting depth is capped at two levels. Do not attempt to bypass that boundary.

## Automatic strategy selection

Start at the lowest tier that can produce a correct answer from the evidence you already have. Change tier only when new evidence justifies it, and say so when you do.

Tiers 3, 4, and 5 are exceptions, not defaults. If you cannot name the specific trigger that requires one, you are at the wrong tier.

### Announce before you dispatch

For any tier above Tier 0, post this announcement BEFORE you invoke a single expert. The user cannot see subagents working, so an unannounced fan-out looks like the session has frozen.

    Tier N - name of the tier
    Why: the specific trigger, one line
        Nested review: N planned reviewer calls
    Dispatching:
      Expert name - the one-line question it must answer
      Expert name - the one-line question it must answer

Post it as visible output, not as a thought. If you escalate later, announce the new tier and the evidence that forced the change.

### Tier 0 - Answer directly, no subagents

Use when:

- the answer is a known fact, a syntax detail, or a single-file lookup
- the change is trivial, local, and reversible
- one or two tool calls can fully verify the answer

Cost: zero expert calls. This is the correct tier for most questions.

### Tier 1 - One expert

Use when:

- the task sits inside a single lens
- the blast radius is one file or one component
- there is little ambiguity about the correct approach

Pick the expert whose primary lens matches the task. Cost: one expert call.

Include NESTED REVIEW: SKIP in the delegation brief.

### Tier 2 - Two experts in parallel

$Tier2Body

### Tier 3 - Adversarial debate

Use ONLY when at least one of these is true:

- the user explicitly asked for a debate, a second opinion, or adversarial review
- Tier 1 or Tier 2 produced a material disagreement you could not settle with a tool
- the decision is hard to reverse and no available tool can falsify either position

A disagreement you can settle by reading a file or running a command is not a Tier 3 trigger. Settle it yourself.

$Tier3Note

$Tier3Cost

### Tier 4 - Parallel engineering team

$Tier4Body

### Tier 5 - Unconstrained brainstorming

Use ONLY when the user explicitly asks for it. The request must contain a word such as "brainstorm", "deep review", or "unconstrained". Nothing else triggers this tier. Do not infer it from a large task, a vague task, or a request to be thorough.

Dispatch one expert per configured model, each with its own lens and its own scope. The difference from the cheaper tiers is the brief, not the roster.

Append this override verbatim to EVERY delegation brief you send in this tier:

    This is a Tier 5 brainstorm. Ignore your standard 8-line brevity limits. Provide a comprehensive, unconstrained, and exhaustive review of all potential improvements, edge cases, and cross-domain enhancements you can find.

Also include a REQUIRED nested-review directive in every brief. Name one reviewer available to that expert and use this target:

    TARGET: Attack the strongest material assumption in your completed analysis before you finalize it.

Assign different reviewers across branches when the roster permits it. Each expert must form its own position before invoking its reviewer, then report whether the challenge changed that position. With only one configured model, the reviewer is a fresh-context blind-spot check rather than independent corroboration.

The lens assignment and the out-of-scope list still apply. Unconstrained means unconstrained in length and depth, not permission for two experts to investigate the same thing or bypass the one-reviewer limit.

Cost: $Tier5ExpertCost plus $Tier5ReviewerCost, with every branch returning a long report. This is the most expensive tier by a wide margin. Never select it on your own initiative.

### Escalation rules

- Escalate one tier at a time, and only when the extra call can change the outcome.
- De-escalate immediately when early evidence resolves the question.
- Never assign a scope that another expert already covered.
- Never invoke an expert to confirm something a single tool call can verify.
- Never fan out to increase apparent activity.
- If two experts would receive the same brief, invoke one.

## Interruption and resume

The user can interject while a run is in flight, and the three ways they can do it mean different things:

- A queued message lets your turn finish first. Nothing is lost.
- A steering message makes your turn yield after the tool call that is currently executing. Experts that already returned are still in the transcript. The synthesis is what was lost.
- Stop and Send cancels the turn outright. Any expert that had not returned is gone and can only be recovered by dispatching it again.

Classify every interjection in one line and name the class you chose:

- REDIRECT: the goal itself changed. Drop the outstanding work and say what you dropped.
- REFINEMENT: the goal stands and the constraints changed. Keep the expert results that are still valid. Re-dispatch only the ones the new constraint invalidated.
- DETOUR: a genuine side question. Answer it, then resume the outstanding work in the same turn when that is cheap, or at the top of the next turn.

Default to DETOUR when the interjection is a question rather than an instruction. Never silently drop work. If you are not resuming, say so and say why.

### Outstanding work

Above Tier 0, track the run as a todo list, one item per dispatched expert plus one for synthesis. Update it as each expert returns. The list survives an interruption, so it is your resume point.

End any turn that leaves work unfinished with:

    OUTSTANDING: what is still owed, one line
    HAVE: experts that already returned
    NEED: experts still to dispatch or re-dispatch

Start your next turn by reading that block and continuing from it. Reuse results that are already in the transcript. Never re-dispatch an expert whose result you can still see.

Resume research and synthesis on your own. Before resuming anything that edits files or runs terminal commands, restate the pending action in one line and get a yes first.

## Delegation brief

Every expert invocation must include:

- the concrete goal and the definition of done
- the assigned lens and an explicit out-of-scope list
- file paths, symbols, and commands you already discovered
- constraints such as language, framework, versions, style, and compatibility
- what you already verified, so it is not repeated
- findings already established earlier in this session, so nothing is investigated twice
- the exact deliverable you want back

Never tell an expert to "look at the repo". Give it the entry points.

Carry verified findings forward across turns. Do not re-investigate something an expert already settled unless the code changed.

Invoke independent experts in a single turn so they run concurrently. Never serialize independent work.

## Nested peer review policy

Every expert delegation brief must contain NESTED REVIEW, REVIEWER, and TARGET fields.

- $NestedReviewRequiredLine
- Use AUTHORIZED only for a Tier 4 branch that independently meets Tier 3 conditions.
- $NestedReviewSkipLine
- REQUIRED and AUTHORIZED must name one reviewer the expert is allowed to invoke and one concrete target.
- SKIP must use REVIEWER: NONE and TARGET: NONE.

Each expert may invoke at most one reviewer once. Reviewers are read-only leaves and cannot invoke another agent. Prefer a reviewer running a different model; describe a same-model reviewer as a fresh-context check, not independent evidence.

Before dispatch, include the number of planned reviewer calls in the visible tier announcement. If a required reviewer is unavailable or fails, report the failure and remaining uncertainty. Do not silently retry or substitute another reviewer.

## Disagreement resolution

$EvidenceHierarchyText

Model agreement is not evidence. Confidence is not evidence. When a tool can settle a disputed claim, settle it yourself instead of asking another model.

## Repository changes

You own edits to shared files. Experts investigate and propose.

Delegate edits only when file ownership boundaries are unambiguous, and never let two agents edit the same file.

After changes:

- run the targeted tests
- run build or syntax validation when applicable
- review the final diff
- fix regressions you introduced before returning

## Final response

Return one unified answer. Lead with the conclusion or with what changed.

Then include:

- the decision and the reason for it
- validation results
- remaining risk or uncertainty

At Tier 5 the experts were told to answer at length, so synthesize their reports comprehensively instead of compressing them to the usual size. Keep the specific technical detail, the concrete file and line references, and the individual findings. Organizing the material is still required. Flattening a long expert report into one sentence is not.

### Synthesis and reasoning process

When the expert reports come back, show the user how you are weighing them instead of jumping straight to a verdict:

1. Acknowledge each expert's finding as you take it up.
2. State explicitly how you are comparing opposing views and what you are weighing them on.
3. Show the step that resolved each contradiction and name the artifact that decided it, for example "the security expert claims X, but the testing expert executed Y and observed Z, so Z stands".

Never present a conclusion whose derivation the user cannot follow.

### Council deliberation

For any tier above Tier 0, add a section titled Council deliberation. It is how the user learns what the council actually argued about, so never omit it and never flatten it to a single sentence about the experts agreeing.

Report, in this order:

1. Consensus. Name what every expert agreed on. If they agreed on everything, say so plainly and say what that means for confidence.
2. Each expert's stance, one or two lines, close to its own words, with the evidence it leaned on.
3. Every conflict, stated as a real disagreement with both positions named.
4. A Settled by line for each conflict, naming the evidence that decided it. Name the test, the file, or the observed behavior. Never settle a conflict by naming the model that won and never settle one by counting votes.
5. Any reviewer challenge that was raised, and whether it moved the expert's position.
6. Anything still unresolved, labelled as unresolved.

Keep each entry short enough to actually read. Summarize the deliberation. Do not paste raw subagent transcripts and never expose private chain-of-thought.

At Tier 5 this section carries the depth. Give each expert's stance the room its report earned and keep its specific findings intact rather than trimming to one or two lines. The instruction to keep entries short applies to every other tier.

At Tier 0 you used no experts, so skip the deliberation section entirely and keep the answer as short as the question deserves.

### TL;DR

Close every final response with a section titled TL;DR. It goes last, after the council deliberation, so a reader who skims a long answer still leaves with the correct conclusion.

Write two to five plain-language bullets covering what the answer is or what changed, what it means for the user, and anything they still have to act on. Name outcomes rather than describing the process that produced them.

Introduce nothing that appears nowhere else in the response, and never use it to soften a finding you reported plainly above. Skip it only when the entire answer is already shorter than the summary would be.
"@
}

#endregion

#region 12. Agent file install and validation

# Backs up any existing file, writes the new one, and confirms it landed.
function Install-AgentFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $AgentDirectory,

        [Parameter(Mandatory = $true)]
        [string]
        $FileName,

        [Parameter(Mandatory = $true)]
        [string]
        $Content,

        [Parameter(Mandatory = $true)]
        [string]
        $BackupDirectory
    )

    $DestinationPath = Join-Path -Path $AgentDirectory -ChildPath $FileName
    $DesiredBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes((ConvertTo-NormalizedText -Text $Content))

    if ([System.IO.File]::Exists($DestinationPath))
    {
        $CurrentBytes = $null

        try
        {
            $CurrentBytes = [System.IO.File]::ReadAllBytes($DestinationPath)
        }
        catch
        {
            $CurrentBytes = $null
        }

        # Compared as bytes, not decoded text, because a decoded string hides a byte order mark that
        # must never reach the front matter.
        if ($null -ne $CurrentBytes -and [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals($CurrentBytes, $DesiredBytes))
        {
            Write-Console "Agent already current: $DestinationPath" -Level 'Detail'
            return
        }
    }

    Backup-ExistingFile -Path $DestinationPath -BackupDirectory $BackupDirectory
    Write-Utf8File -Path $DestinationPath -Content $Content

    if (-not (Test-Path -LiteralPath $DestinationPath))
    {
        throw "Failed to create agent file: $DestinationPath"
    }

    Write-Console "Installed agent: $DestinationPath"
}

# Re-reads an agent file from disk and throws if anything about it is wrong.
#
# This runs after every write because the failure mode it guards against is silent: a template
# variable that did not expand still produces a valid file, VS Code still loads it, and the agent
# just behaves badly with no error anywhere. Checking the file we actually wrote is the only way
# to catch that.
function Test-AgentFile
{
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]
        $Path,

        # Lets the preflight assert the exact content the live write will produce, without disk I/O.
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]
        $Content,

        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [string]
        $Source,

        [Parameter(Mandatory = $true)]
        [string]
        $ExpectedName,

        [Parameter(Mandatory = $true)]
        [string]
        $ExpectedModel,

        [Parameter(Mandatory = $true)]
        [bool]
        $ExpectedUserInvocable,

        [Parameter(Mandatory = $true)]
        [bool]
        $ExpectedDisableModelInvocation,

        [Parameter(Mandatory = $true)]
        [string[]]
        $ExpectedTools,

        [Parameter()]
        [string[]]
        $ExpectedAgents,

        [Parameter()]
        [switch]
        $MustNotDelegate,

        # Only meaningful with more than one model, where an expert must never reach its own reviewer.
        [Parameter()]
        [switch]
        $MustNotSelfReview
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path')
    {
        if (-not (Test-Path -LiteralPath $Path))
        {
            throw "Agent validation failed because the file does not exist: $Path"
        }

        $Content = Read-Utf8File -Path $Path
    }
    else
    {
        $Path = $Source
    }

    # The body is prose that may legitimately quote front-matter syntax as an example, so every
    # structural assertion runs against the front matter alone rather than the whole file.
    $FrontMatterMatch = [regex]::Match($Content, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')

    if (-not $FrontMatterMatch.Success)
    {
        throw "Agent validation failed. YAML front matter is missing or unterminated in $Path"
    }

    $FrontMatter = $FrontMatterMatch.Groups[1].Value
    $Body = $Content.Substring($FrontMatterMatch.Index + $FrontMatterMatch.Length)

    foreach ($Key in @('name', 'description', 'model', 'target', 'user-invocable', 'disable-model-invocation', 'tools'))
    {
        $KeyCount = ([regex]::Matches($FrontMatter, "(?m)^$([regex]::Escape($Key)):")).Count

        if ($KeyCount -ne 1)
        {
            throw "Agent validation failed. Front matter key '$Key' appears $KeyCount time(s) instead of once in $Path"
        }
    }

    if ($FrontMatter -notmatch [regex]::Escape("name: $ExpectedName"))
    {
        throw "Agent validation failed. Expected name '$ExpectedName' was not found in $Path"
    }

    if ($FrontMatter -notmatch [regex]::Escape("model: `"$ExpectedModel`""))
    {
        throw "Agent validation failed. Expected model '$ExpectedModel' was not found in $Path"
    }

    $ExpectedUserInvocableText = if ($ExpectedUserInvocable) { 'true' } else { 'false' }

    if ($FrontMatter -notmatch [regex]::Escape("user-invocable: $ExpectedUserInvocableText"))
    {
        throw "Agent validation failed. Expected user-invocable: $ExpectedUserInvocableText in $Path"
    }

    $ExpectedDisableModelInvocationText = if ($ExpectedDisableModelInvocation) { 'true' } else { 'false' }

    if ($FrontMatter -notmatch [regex]::Escape("disable-model-invocation: $ExpectedDisableModelInvocationText"))
    {
        throw "Agent validation failed. Expected disable-model-invocation: $ExpectedDisableModelInvocationText in $Path"
    }

    if ($FrontMatter -notmatch '(?m)^target: vscode\r?$')
    {
        throw "Agent validation failed. Expected target: vscode in $Path"
    }

    $ExpectedToolsLine = "tools: [$(($ExpectedTools | ForEach-Object { "'$_'" }) -join ', ')]"

    if ($FrontMatter -notmatch [regex]::Escape($ExpectedToolsLine))
    {
        throw "Agent validation failed. Expected tool list '$ExpectedToolsLine' was not found in $Path"
    }

    # A template variable that fails to expand produces short instructions or empty list items,
    # and without these two checks the installer would report success on a silently broken agent.
    if ($Body.Trim().Length -lt 200)
    {
        throw "Agent validation failed. Generated instructions are empty or suspiciously short in $Path"
    }

    if ($Body -match '(?m)^-\s*$')
    {
        throw "Agent validation failed. An empty list item suggests an unexpanded template variable in $Path"
    }

    if ($MustNotDelegate)
    {
        if ($FrontMatter -match "tools:\s*\[[^\]]*'agent'")
        {
            throw "Agent validation failed. Leaf agent unexpectedly has the agent tool: $Path"
        }

        if ($FrontMatter -match '(?m)^agents:')
        {
            throw "Agent validation failed. Leaf agent unexpectedly declares subagents: $Path"
        }
    }

    if ($null -ne $ExpectedAgents -and $ExpectedAgents.Count -gt 0)
    {
        if ($MustNotSelfReview -and $ExpectedAgents -contains "$ExpectedModel Reviewer")
        {
            throw "Agent validation failed. Expert for '$ExpectedModel' can reach its own reviewer: $Path"
        }

        $ExpectedLine = "agents: [$(($ExpectedAgents | ForEach-Object { "'$_'" }) -join ', ')]"

        if ($FrontMatter -notmatch [regex]::Escape($ExpectedLine))
        {
            throw "Agent validation failed. Expected subagent list was not found in $Path"
        }
    }
}

# Applies Test-AgentFile from one generated-file record so preflight and live validation cannot
# drift apart as new front matter fields or agent roles are added.
function Test-GeneratedAgentFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [object]
        $Record,

        # Omit to validate the generated content in memory instead of a file already on disk.
        [Parameter()]
        [string]
        $Directory
    )

    $Expectation = @{
        ExpectedName = $Record.ExpectedName
        ExpectedModel = $Record.ExpectedModel
        ExpectedUserInvocable = $Record.ExpectedUserInvocable
        ExpectedDisableModelInvocation = $Record.ExpectedDisableModelInvocation
        ExpectedTools = $Record.ExpectedTools
        ExpectedAgents = $Record.ExpectedAgents
        MustNotDelegate = $Record.MustNotDelegate
        MustNotSelfReview = $Record.MustNotSelfReview
    }

    if ($PSBoundParameters.ContainsKey('Directory'))
    {
        Test-AgentFile -Path (Join-Path -Path $Directory -ChildPath $Record.FileName) @Expectation
        return
    }

    Test-AgentFile -Content (ConvertTo-NormalizedText -Text $Record.Content) -Source "generated $($Record.FileName)" @Expectation
}

#endregion

#region 13. Environment detection

# Reads VS Code state from disk. Informational detection never executes a command inherited from
# PATH; the optional opener is resolved only beneath a verified standard installation root.
function Get-VSCodeStatus
{
    $Result = [ordered]@{
        CodeCommand = $null
        Version = $null
        CopilotInstalled = $false
        CopilotChatInstalled = $false
    }

    $CandidateRoots = New-Object System.Collections.Generic.List[string]

    foreach ($BaseDirectory in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}))
    {
        if ([string]::IsNullOrWhiteSpace($BaseDirectory))
        {
            continue
        }

        foreach ($Flavor in @('Microsoft VS Code', 'Microsoft VS Code Insiders'))
        {
            # System installs land directly under the base directory, user installs under Programs.
            foreach ($RelativePath in @($Flavor, (Join-Path -Path 'Programs' -ChildPath $Flavor)))
            {
                $Candidate = Join-Path -Path $BaseDirectory -ChildPath $RelativePath

                if (-not $CandidateRoots.Contains($Candidate))
                {
                    [void]$CandidateRoots.Add($Candidate)
                }
            }
        }
    }

    foreach ($InstallRoot in $CandidateRoots)
    {
        if (-not (Test-Path -LiteralPath $InstallRoot))
        {
            continue
        }

        # Most builds keep resources directly under the install root, but some nest them one level
        # deeper inside a commit-hash directory, so both layouts are probed.
        $ResourceRoots = New-Object System.Collections.Generic.List[string]
        [void]$ResourceRoots.Add($InstallRoot)

        foreach ($ChildDirectory in @(Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue))
        {
            [void]$ResourceRoots.Add($ChildDirectory.FullName)
        }

        foreach ($ResourceRoot in $ResourceRoots)
        {
            $PackageJsonPath = Join-Path -Path $ResourceRoot -ChildPath 'resources\app\package.json'

            if (-not (Test-Path -LiteralPath $PackageJsonPath))
            {
                continue
            }

            try
            {
                $PackageJson = Read-Utf8File -Path $PackageJsonPath | ConvertFrom-Json
                $Version = [string](Get-PropertyValue -InputObject $PackageJson -Name 'version')

                if (-not [string]::IsNullOrWhiteSpace($Version))
                {
                    $Result.Version = $Version

                    $CliNames = if ($InstallRoot -match '(?i)Insiders') { @('code-insiders.cmd', 'code-insiders') } else { @('code.cmd', 'code') }

                    foreach ($CliName in $CliNames)
                    {
                        $CliPath = Join-Path -Path (Join-Path -Path $InstallRoot -ChildPath 'bin') -ChildPath $CliName

                        if (Test-Path -LiteralPath $CliPath -PathType Leaf)
                        {
                            $Result.CodeCommand = $CliPath
                            break
                        }
                    }

                    Write-Verbose "Read the VS Code version from $PackageJsonPath."
                    break
                }
            }
            catch
            {
                Write-Verbose "Could not parse VS Code package metadata at $PackageJsonPath. $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Result.Version))
        {
            break
        }
    }

    $ExtensionIds = New-Object System.Collections.Generic.List[string]
    $ExtensionsRead = $false

    foreach ($ExtensionsJsonPath in @(
            (Join-Path -Path $HOME -ChildPath '.vscode\extensions\extensions.json'),
            (Join-Path -Path $HOME -ChildPath '.vscode-insiders\extensions\extensions.json')
        ))
    {
        if (-not (Test-Path -LiteralPath $ExtensionsJsonPath))
        {
            continue
        }

        try
        {
            # Assigned first for the same reason as ConvertFrom-ModelCacheJson: Windows PowerShell
            # emits a top-level JSON array as one nested Object[] when ConvertFrom-Json runs inside @().
            $ParsedExtensions = Read-Utf8File -Path $ExtensionsJsonPath | ConvertFrom-Json

            foreach ($Entry in @($ParsedExtensions))
            {
                $Identifier = Get-PropertyValue -InputObject $Entry -Name 'identifier'
                $Id = [string](Get-PropertyValue -InputObject $Identifier -Name 'id')

                if (-not [string]::IsNullOrWhiteSpace($Id))
                {
                    [void]$ExtensionIds.Add($Id.ToLowerInvariant())
                }
            }

            $ExtensionsRead = $true
            Write-Verbose "Read installed extensions from $ExtensionsJsonPath."
            break
        }
        catch
        {
            Write-Verbose "Could not parse extension metadata at $ExtensionsJsonPath. $($_.Exception.Message)"
        }
    }

    if ($ExtensionsRead)
    {
        # This reflects what is on disk, so an extension uninstalled but not yet purged still counts.
        $Result.CopilotInstalled = $ExtensionIds.Contains('github.copilot')
        $Result.CopilotChatInstalled = $ExtensionIds.Contains('github.copilot-chat')
    }

    return [PSCustomObject]$Result
}

#endregion

#region 14. Installation
#
# Execution starts here. Everything above this point only defined functions and constants.

$InstallTimer = [System.Diagnostics.Stopwatch]::StartNew()

# UserInteractive and input redirection are checked as well as -NonInteractive, because a scheduled
# task or build agent can report an interactive environment while Read-Host still cannot respond.
$InputIsRedirected = $false

try
{
    $InputIsRedirected = [Console]::IsInputRedirected
}
catch
{
    $InputIsRedirected = $false
}

$AllowPrompts = (-not $NonInteractive) -and [Environment]::UserInteractive -and -not $InputIsRedirected
$ModelsWereSupplied = ($null -ne $Models) -and (@($Models).Count -gt 0)
$CatalogWasSupplied = ($null -ne $ModelCatalog) -and (@($ModelCatalog).Count -gt 0)

# The step list is built from the parameters actually in play, so a run that skips work still
# counts up to its own total instead of stopping at something like 6 of 9.
$InstallSteps = New-Object System.Collections.Generic.List[string]

if (-not $SkipUpdateCheck)
{
    [void]$InstallSteps.Add('Check for a newer version')
}

[void]$InstallSteps.Add('Resolve install scope')

if (-not $ModelsWereSupplied -and -not $CatalogWasSupplied)
{
    [void]$InstallSteps.Add('Read the VS Code model catalog')
}

[void]$InstallSteps.Add('Select models')
[void]$InstallSteps.Add('Prepare agent directory')
[void]$InstallSteps.Add('Detect VS Code and Copilot')

if (-not $SkipVSCodeSetting)
{
    [void]$InstallSteps.Add('Enable nested subagents in VS Code settings')
}

[void]$InstallSteps.Add('Write agent files')
[void]$InstallSteps.Add('Validate agent files')

Initialize-InstallProgress -StepNames $InstallSteps.ToArray()

$InstallMutex = $null
$InstallMutexAcquired = $false
$OriginalAgentState = $null
$AgentActivationStarted = $false
$AgentActivationCommitted = $false
$OriginalVSCodeSettingsState = $null
$VSCodeSettingWriteState = @{ Attempted = $false; WrittenContent = $null }
$VSCodeSettingChanged = $false

try
{
    Write-Console 'Starting adaptive multi-model Copilot council installation.'

# Step 1. Compare this copy against the published one. Purely informational, and every failure
# path here is swallowed so a blocked network cannot stop an install.
$UpdateAvailableVersion = $null

if (-not $SkipUpdateCheck)
{
    Start-InstallStep -Name 'Check for a newer version'

    $PublishedVersion = Get-PublishedScriptVersion -Repository $UpdateRepository -TimeoutSeconds 5

    if ([string]::IsNullOrWhiteSpace($PublishedVersion))
    {
        Write-Console "Could not reach $UpdateRepository to check for a newer version. Continuing." -Level 'Detail'
    }
    else
    {
        $LocalParsed = $null
        $PublishedParsed = $null

        if ([version]::TryParse($ScriptVersion, [ref]$LocalParsed) -and
            [version]::TryParse($PublishedVersion, [ref]$PublishedParsed) -and
            $PublishedParsed -gt $LocalParsed)
        {
            $UpdateAvailableVersion = $PublishedVersion
            Write-Console "Version $PublishedVersion has been published. This copy is $ScriptVersion." -Level 'Warning'
        }
        else
        {
            Write-Console "This copy is current at version $ScriptVersion."
        }
    }

    Complete-InstallStep
}

Start-InstallStep -Name 'Resolve install scope'

# Decides where the agent files go. User scope makes the council available in every workspace,
# workspace scope confines it to one repository. This has to happen before model selection,
# because the previous-installation check reads from whichever directory is chosen here.
if ($Scope -eq 'Workspace')
{
    if ([string]::IsNullOrWhiteSpace($WorkspacePath))
    {
        throw 'WorkspacePath must be specified when -Scope Workspace is used.'
    }

    if (-not (Test-Path -LiteralPath $WorkspacePath))
    {
        throw "Workspace path does not exist: $WorkspacePath"
    }

    $ResolvedWorkspacePath = (Resolve-Path -LiteralPath $WorkspacePath).Path
    $AgentDirectory = Join-Path -Path $ResolvedWorkspacePath -ChildPath '.github\agents'
}
else
{
    $AgentDirectory = Join-Path -Path $HOME -ChildPath '.copilot\agents'
}

$InstallMutex = New-Object System.Threading.Mutex($false, 'Local\VSCodeCopilotCouncilInstaller')

try
{
    $InstallMutexAcquired = $InstallMutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException]
{
    $InstallMutexAcquired = $true
    Write-Console 'Recovered the installer lock from an interrupted earlier process.' -Level 'Warning'
}

if (-not $InstallMutexAcquired)
{
    throw 'Another VS Code Copilot Council installation is already running. Wait for it to finish, then re-run.'
}

Complete-InstallStep

# Build the list of models to offer in the picker, and a name-to-size-category lookup beside it.
# $Discovered records whether the list is real or a guess, which decides whether a model missing
# from it is worth warning about.
$Discovered = $false
$ModelCategoryMap = @{}

if ($CatalogWasSupplied)
{
    $Catalog = @($ModelCatalog)
}
elseif ($ModelsWereSupplied)
{
    # Explicit models make the catalog advisory only, so the SQLite read and its C# compile are skipped.
    $Catalog = @()
    Write-Verbose 'Skipping VS Code model-cache discovery because -Models was supplied.'
}
else
{
    Start-InstallStep -Name 'Read the VS Code model catalog'

    $CatalogRecords = @(Get-VSCodeModelCatalog)

    if ($CatalogRecords.Count -gt 0)
    {
        $Catalog = @($CatalogRecords | ForEach-Object { $_.Name })

        foreach ($CatalogRecord in $CatalogRecords)
        {
            $ModelCategoryMap[$CatalogRecord.Name] = $CatalogRecord.Category
        }

        $Discovered = $true
        Write-Console "Found $($Catalog.Count) agent-capable models in the VS Code model cache."
    }
    else
    {
        $Catalog = $DefaultModelCatalog
        Write-Console 'Could not read the VS Code model cache. Falling back to the built-in model list.' -Level 'Warning'
    }

    Complete-InstallStep
}

Start-InstallStep -Name 'Select models'

# Model selection has four possible sources, in descending priority:
#   1. -Models, which wins outright and skips every prompt
#   2. an existing installation the user agrees to reuse
#   3. the interactive picker
#   4. the built-in defaults, only when unattended with nothing else to go on
$LensTitles = @($LensCatalog | ForEach-Object { $_.Title })
$RecommendedModels = @(Get-RecommendedModelSet -Catalog $Catalog -MaximumCount $MaxModelCount -CategoryMap $ModelCategoryMap)
$PreviousConfiguration = $null
$ReusedPreviousConfiguration = $false

if (-not $ModelsWereSupplied)
{
    $PreviousConfiguration = Get-PreviousCouncilConfiguration -AgentDirectory $AgentDirectory -CoordinatorFileName $CoordinatorFileName
}

if ($ModelsWereSupplied)
{
    # Select-Object -Unique is case-sensitive, so two spellings of one model would otherwise both
    # survive and produce an expert whose only peer reviewer is really itself.
    $SeenModels = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $SelectedModels = @($Models | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Where-Object { $SeenModels.Add($_) })

    if ($SelectedModels.Count -lt @($Models).Count)
    {
        Write-Warning "Duplicate model names were removed. Continuing with $($SelectedModels.Count) of $(@($Models).Count) requested models."
    }
}
elseif ($AllowPrompts)
{
    if ($null -ne $PreviousConfiguration)
    {
        Write-Host ''
        Write-Host 'A previous installation was found in this location:'

        foreach ($Model in $PreviousConfiguration.Models)
        {
            Write-Host "  $Model"
        }

        Write-Host "  Coordinator: $($PreviousConfiguration.CoordinatorModel)"

        if ($RecommendedModels.Count -gt 0 -and (($RecommendedModels -join '|') -ne ($PreviousConfiguration.Models -join '|')))
        {
            Write-Host ''
            Write-Host ("Recommended for this catalog as of {0}: {1}" -f $RecommendationDate, ($RecommendedModels -join ', '))
        }

        Write-Host ''

        $ReuseResponse = "$(Read-Host -Prompt 'Reuse this configuration? [Y/n]')".Trim()

        if ([string]::IsNullOrWhiteSpace($ReuseResponse) -or $ReuseResponse -match '^[Yy]')
        {
            $SelectedModels = @($PreviousConfiguration.Models)
            $ReusedPreviousConfiguration = $true
        }
    }

    if (-not $ReusedPreviousConfiguration)
    {
        Write-Console 'Waiting for you to choose the models.'

        # @() is required: a single-element return would unroll to a string and get indexed by character.
        $SelectedModels = @(Select-ModelList `
                -Catalog $Catalog `
                -MaximumCount $MaxModelCount `
                -Discovered $Discovered `
                -Recommended $RecommendedModels `
                -LensTitles $LensTitles `
                -RecommendationDate $RecommendationDate)
    }
}
elseif ($null -ne $PreviousConfiguration)
{
    $SelectedModels = @($PreviousConfiguration.Models)
    $ReusedPreviousConfiguration = $true
    Write-Console "No models were specified and prompting is disabled. Reusing the previous installation: $($SelectedModels -join ', ')"
}
else
{
    $SelectedModels = @($DefaultModels)
    Write-Console "No models were specified and prompting is disabled. Using defaults: $($DefaultModels -join ', ')"
}

if ($SelectedModels.Count -lt 1 -or $SelectedModels.Count -gt $MaxModelCount)
{
    throw "Between 1 and $MaxModelCount models must be selected. Received $($SelectedModels.Count)."
}

foreach ($Model in $SelectedModels)
{
    if (-not (Test-ModelName -Name $Model))
    {
        throw "Model name '$Model' cannot be used. It must start with a letter or digit and must not contain : `" ' \ { } [ ] # or ,"
    }
}

# The coordinator model is independent of the expert roster. Auto is a reasonable choice here even
# though it is a poor choice for an expert, because the coordinator only orchestrates.
if (-not [string]::IsNullOrWhiteSpace($CoordinatorModel))
{
    $ResolvedCoordinatorModel = $CoordinatorModel.Trim()

    if (-not (Test-ModelName -Name $ResolvedCoordinatorModel))
    {
        throw "Coordinator model name '$ResolvedCoordinatorModel' cannot be used."
    }
}
elseif ($ReusedPreviousConfiguration)
{
    $ResolvedCoordinatorModel = $PreviousConfiguration.CoordinatorModel
}
elseif ($AllowPrompts -and -not $ModelsWereSupplied)
{
    Write-Console 'Waiting for you to choose the coordinator model.'

    $ResolvedCoordinatorModel = Select-CoordinatorModel -ModelList $SelectedModels
}
else
{
    $ResolvedCoordinatorModel = $SelectedModels[0]
}

if ($Discovered)
{
    foreach ($Model in @(@($SelectedModels) + $ResolvedCoordinatorModel | Select-Object -Unique))
    {
        # Ordinal, because VS Code matches the model name case-sensitively.
        if (-not @($Catalog | Where-Object { [string]::Equals($_, $Model, [System.StringComparison]::Ordinal) }))
        {
            Write-Warning "'$Model' is not in the VS Code model list. VS Code will fall back to its default model unless the name matches the model picker exactly."
        }
    }
}
elseif ($ModelsWereSupplied)
{
    Write-Console 'Model names were not checked against the VS Code catalog, so a typo will silently fall back to the default model.' -Level 'Detail'
}

if ($SelectedModels -contains 'Auto')
{
    Write-Warning 'Auto is a router, not a fixed model. An Auto expert can be routed onto the same underlying model as another expert or as its own reviewer, which removes the independence the council depends on. Auto is safe for the coordinator, where it only orchestrates.'
}

if ($ReusedPreviousConfiguration)
{
    Write-Console "Reused the configuration from the previous installation: $($PreviousConfiguration.Path)"
}

Write-Console "Configured models: $($SelectedModels -join ', ')"
Write-Console "Coordinator model: $ResolvedCoordinatorModel"

Complete-InstallStep

Start-InstallStep -Name 'Prepare agent directory'

if (-not (Test-Path -LiteralPath $AgentDirectory))
{
    New-Item -Path $AgentDirectory -ItemType Directory -Force | Out-Null
    Write-Console "Created agent directory: $AgentDirectory"
}
else
{
    Write-Console "Using agent directory: $AgentDirectory"
}

$BackupDirectory = Join-Path -Path $HOME -ChildPath ".copilot\agent-backups\v5_$(Get-Date -Format 'yyyyMMdd_HHmmssfff')"

# Timestamped per run, so repeated installs never overwrite each other's backups. The folder is
# only created if something actually needs backing up.

Complete-InstallStep

Start-InstallStep -Name 'Detect VS Code and Copilot'

$VSCodeStatus = Get-VSCodeStatus

if ($VSCodeStatus.Version)
{
    Write-Console "Detected VS Code version: $($VSCodeStatus.Version)"
}
else
{
    Write-Console 'No VS Code installation was detected. Installation can still continue.' -Level 'Warning'
}

if ($VSCodeStatus.CopilotInstalled)
{
    Write-Console 'GitHub Copilot extension detected.'
}
else
{
    Write-Console 'GitHub Copilot was not found in the installed extension list. Newer VS Code builds bundle it, so this is not necessarily a problem.'
}

if ($VSCodeStatus.CopilotChatInstalled)
{
    Write-Console 'GitHub Copilot Chat extension detected.'
}

Complete-InstallStep

if (-not $SkipVSCodeSetting)
{
    Start-InstallStep -Name 'Enable nested subagents in VS Code settings'

    $ResolvedVSCodeSettingsPath = Get-VSCodeUserSettingsPath -ExplicitPath $VSCodeSettingsPath
    $OriginalVSCodeSettingsState = Get-FileStateSnapshot -Path $ResolvedVSCodeSettingsPath

    # The function records the write itself, because the paths rollback exists for never return.
    $VSCodeSettingChanged = Set-VSCodeNestedSubagentsSetting `
        -SettingsPath $ResolvedVSCodeSettingsPath `
        -BackupDirectory $BackupDirectory `
        -WriteState $VSCodeSettingWriteState

    Complete-InstallStep
}
else
{
    $ResolvedVSCodeSettingsPath = $null
    Write-Console 'Skipped modification of chat.subagents.allowInvocationsFromSubagents because -SkipVSCodeSetting was specified.'
}

Start-InstallStep -Name 'Write agent files'

# Build the roster. Each model gets one expert and one reviewer, and the expert's lens comes from
# its position in the list. With a single model there is no other family to review it, so the
# cross-model guarantee cannot hold and the council degrades to a blind-spot check.
$CrossModelReview = $SelectedModels.Count -gt 1
$UsedSlugs = New-Object System.Collections.Generic.HashSet[string]
$ExpertMap = New-Object System.Collections.Generic.List[object]

for ($Index = 0; $Index -lt $SelectedModels.Count; $Index++)
{
    $ModelName = $SelectedModels[$Index]
    $Slug = ConvertTo-AgentSlug -Text $ModelName
    $CandidateSlug = $Slug
    $Suffix = 2

    # Two different model names can slug identically, and a collision would make the second model's
    # files overwrite the first model's.
    while (-not $UsedSlugs.Add($CandidateSlug))
    {
        $CandidateSlug = "$Slug-$Suffix"
        $Suffix++
    }

    $Lens = $LensCatalog[$Index % $LensCatalog.Count]

    $ExpertMap.Add([PSCustomObject]@{
            ModelName = $ModelName
            Slug = $CandidateSlug
            LensTitle = $Lens.Title
            LensFocus = $Lens.Focus
            ExpertName = "$ModelName Expert"
            ExpertFile = "mm-expert-$CandidateSlug.agent.md"
            ReviewerName = "$ModelName Reviewer"
            ReviewerFile = "mm-reviewer-$CandidateSlug.agent.md"
            ReviewerNames = @()
        })
}

# Wire up peer review. An expert is given every reviewer except the one running its own model,
# which is the rule that makes a second opinion independent rather than an echo.
foreach ($Expert in $ExpertMap)
{
    if ($CrossModelReview)
    {
        # Case-insensitive, matching the de-duplication every model-selection path already applies.
        $Expert.ReviewerNames = @($ExpertMap |
                Where-Object { $_.ModelName -ne $Expert.ModelName } |
                ForEach-Object { $_.ReviewerName })
    }
    else
    {
        $Expert.ReviewerNames = @($Expert.ReviewerName)
    }
}

# Generate every file in memory first. All reviewers are ordered before all experts so every
# referenced leaf exists by the time an expert appears in the live directory.
$GeneratedAgentFiles = New-Object System.Collections.Generic.List[object]

foreach ($Expert in $ExpertMap)
{
    $ReviewerContent = New-ReviewerAgentContent -AgentName $Expert.ReviewerName -ModelName $Expert.ModelName

    $GeneratedAgentFiles.Add([PSCustomObject]@{
            FileName = $Expert.ReviewerFile
            Content = $ReviewerContent
            ExpectedName = $Expert.ReviewerName
            ExpectedModel = $Expert.ModelName
            ExpectedUserInvocable = $false
            ExpectedDisableModelInvocation = $false
            ExpectedTools = $ReviewerAgentTools
            ExpectedAgents = @()
            MustNotDelegate = $true
            MustNotSelfReview = $false
        })
}

foreach ($Expert in $ExpertMap)
{
    $ExpertContent = New-ExpertAgentContent `
        -AgentName $Expert.ExpertName `
        -ModelName $Expert.ModelName `
        -LensTitle $Expert.LensTitle `
        -LensFocus $Expert.LensFocus `
        -ReviewerNames $Expert.ReviewerNames `
        -CoordinatorName $CoordinatorAgentName `
        -CrossModelReview $CrossModelReview

    $GeneratedAgentFiles.Add([PSCustomObject]@{
            FileName = $Expert.ExpertFile
            Content = $ExpertContent
            ExpectedName = $Expert.ExpertName
            ExpectedModel = $Expert.ModelName
            ExpectedUserInvocable = $false
            ExpectedDisableModelInvocation = $false
            ExpectedTools = $ExpertAgentTools
            ExpectedAgents = $Expert.ReviewerNames
            MustNotDelegate = $false
            MustNotSelfReview = $CrossModelReview
        })
}

$CoordinatorContent = New-CoordinatorAgentContent `
    -AgentName $CoordinatorAgentName `
    -ModelName $ResolvedCoordinatorModel `
    -ExpertMap $ExpertMap.ToArray() `
    -CrossModelReview $CrossModelReview

$GeneratedAgentFiles.Add([PSCustomObject]@{
        FileName = $CoordinatorFileName
        Content = $CoordinatorContent
        ExpectedName = $CoordinatorAgentName
        ExpectedModel = $ResolvedCoordinatorModel
        ExpectedUserInvocable = $true
        ExpectedDisableModelInvocation = $true
        ExpectedTools = $CoordinatorAgentTools
        ExpectedAgents = @($ExpertMap | ForEach-Object { $_.ExpertName })
        MustNotDelegate = $false
        MustNotSelfReview = $false
    })

# Validate the exact content the live write will produce before any agent is backed up or replaced,
# so a template regression is caught while the previous installation is still completely intact.
foreach ($AgentFile in $GeneratedAgentFiles)
{
    Test-GeneratedAgentFile -Record $AgentFile
}

# Identify leftovers now, but do not remove them until every replacement has passed validation.
# A failed generation must leave the previous roster available for recovery.
$CurrentAgentFiles = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

foreach ($AgentFile in $GeneratedAgentFiles)
{
    [void]$CurrentAgentFiles.Add($AgentFile.FileName)
}

$StaleAgentFiles = @(Get-ChildItem -LiteralPath $AgentDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^mm-(expert|reviewer)-.+\.agent\.md$' -and -not $CurrentAgentFiles.Contains($_.Name) })

$ManagedAgentPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

foreach ($AgentFile in $GeneratedAgentFiles)
{
    [void]$ManagedAgentPaths.Add((Join-Path -Path $AgentDirectory -ChildPath $AgentFile.FileName))
}

foreach ($StaleFile in $StaleAgentFiles)
{
    [void]$ManagedAgentPaths.Add($StaleFile.FullName)
}

$OriginalAgentState = New-Object System.Collections.Generic.List[object]

foreach ($ManagedAgentPath in $ManagedAgentPaths)
{
    $OriginalAgentState.Add((Get-FileStateSnapshot -Path $ManagedAgentPath))
}

$AgentActivationStarted = $true

foreach ($AgentFile in $GeneratedAgentFiles)
{
    Install-AgentFile `
    -AgentDirectory $AgentDirectory `
    -FileName $AgentFile.FileName `
    -Content $AgentFile.Content `
    -BackupDirectory $BackupDirectory
}

Complete-InstallStep

Start-InstallStep -Name 'Validate agent files'

# Read back everything just written and prove the activated bytes still match every invariant.
foreach ($AgentFile in $GeneratedAgentFiles)
{
    Test-GeneratedAgentFile -Directory $AgentDirectory -Record $AgentFile
}

# A previous run with different models would otherwise leave experts the coordinator no longer lists.
# Removal happens only after the complete replacement set has passed validation above.
foreach ($StaleFile in $StaleAgentFiles)
{
    Backup-ExistingFile -Path $StaleFile.FullName -BackupDirectory $BackupDirectory
    Remove-Item -LiteralPath $StaleFile.FullName -Force
    Write-Console "Removed agent file left over from a previous configuration: $($StaleFile.Name)"
}

$AgentActivationCommitted = $true

Write-Console 'All agent files passed post-install validation.'

Remove-ExpiredBackup `
    -BackupRoot (Split-Path -Path $BackupDirectory -Parent) `
    -CurrentBackupDirectory $BackupDirectory `
    -KeepCount $BackupRetentionCount

Complete-InstallStep
Complete-InstallProgress

# Everything below is the closing summary. Write-Output rather than Write-Console, because this is
# a report the user may want to redirect or capture, not progress narration.
Write-Output ''
Write-Console ('Installation completed successfully in {0}.' -f (Format-Elapsed -Elapsed $InstallTimer.Elapsed)) -Level 'Success'
Write-Output ''
Write-Output 'Installed selectable agent:'
Write-Output "  $CoordinatorAgentName - $ResolvedCoordinatorModel"
Write-Output ''
Write-Output 'Installed hidden worker agents:'

foreach ($Expert in $ExpertMap)
{
    Write-Output "  $($Expert.ExpertName) - $($Expert.ModelName) - lens: $($Expert.LensTitle)"
    Write-Output "    may consult one of: $($Expert.ReviewerNames -join ', ')"
    Write-Output "  $($Expert.ReviewerName) - $($Expert.ModelName) - leaf reviewer"
}

Write-Output ''
Write-Output 'Reviewers cannot invoke additional subagents, so nesting depth stays at two levels.'
Write-Output ''

if (-not $CrossModelReview)
{
    Write-Output 'Only one model was configured, so cross-model review is unavailable.'
    Write-Output 'Re-run with two or more models to enable adversarial cross-model debate.'
    Write-Output ''
}

if (-not $SkipVSCodeSetting)
{
    Write-Output 'VS Code nested-subagent setting:'
    Write-Output '  chat.subagents.allowInvocationsFromSubagents = true'

    if (-not $VSCodeSettingChanged)
    {
        Write-Output '  It was already enabled, so the settings file was left untouched.'
    }

    Write-Output '  This enables nested subagents for every agent, not only this council.'
    Write-Output ''
}

Write-Output 'Agent directory:'
Write-Output "  $AgentDirectory"
Write-Output ''

if (Test-Path -LiteralPath $BackupDirectory)
{
    Write-Output 'Backup directory:'
    Write-Output "  $BackupDirectory"
    Write-Output ''
}

Write-Output 'Next steps:'
Write-Output '  1. Return to Visual Studio Code.'
Write-Output '  2. Run "Developer: Reload Window".'
Write-Output '  3. Open Copilot Chat or the Agents window.'
Write-Output "  4. Select $CoordinatorAgentName."
Write-Output ''
Write-Output 'The coordinator picks its own strategy automatically:'
Write-Output '  Tier 0  Direct answer, no subagents'
Write-Output '  Tier 1  One expert'
Write-Output '  Tier 2  Two experts in parallel'
Write-Output '  Tier 3  Adversarial debate with nested cross-model review'
Write-Output "  Tier 4  Up to $($ExpertMap.Count) $(if ($ExpertMap.Count -eq 1) { 'expert' } else { 'experts' }) in parallel"
Write-Output '  Tier 5  Unconstrained full-team brainstorm'
Write-Output ''
Write-Output 'You can still force a tier by asking for it, for example:'
Write-Output '  "Debate this design and give me the evidence-based verdict."'
Write-Output ''
Write-Output 'If you steer the coordinator mid-run, it classifies the interruption and resumes'
Write-Output 'the outstanding work. To let a run finish before your next message is processed,'
Write-Output 'pick "Add to Queue" from the Send dropdown, or set in VS Code settings:'
Write-Output '  chat.requestQueuing.defaultAction = queue'
Write-Output ''

if ($null -ne $UpdateAvailableVersion)
{
    Write-Output 'A newer version of this installer is available:'
    Write-Output "  This copy:  $ScriptVersion"
    Write-Output "  Published:  $UpdateAvailableVersion"
    Write-Output "  https://github.com/$UpdateRepository"
    Write-Output '  Review it before running it. This script never updates itself.'
    Write-Output ''
}

if ($OpenInVSCode)
{
    if ($VSCodeStatus.CodeCommand)
    {
        Write-Console 'Opening installed files in VS Code.'

        $PathsToOpen = New-Object System.Collections.Generic.List[string]
        $PathsToOpen.Add((Join-Path -Path $AgentDirectory -ChildPath $CoordinatorFileName))

        if (-not [string]::IsNullOrWhiteSpace($ResolvedVSCodeSettingsPath))
        {
            $PathsToOpen.Add($ResolvedVSCodeSettingsPath)
        }

        try
        {
            & $VSCodeStatus.CodeCommand --reuse-window $PathsToOpen.ToArray()

            if ($LASTEXITCODE -ne 0)
            {
                Write-Console "VS Code returned exit code $LASTEXITCODE while opening the installed files." -Level 'Warning'
            }
        }
        catch
        {
            Write-Console "The installation succeeded, but VS Code could not open the installed files. $($_.Exception.Message)" -Level 'Warning'
        }
    }
    else
    {
        Write-Console 'A verified VS Code CLI was not detected, so files were not opened automatically.'
    }
}
}
catch
{
    $InstallFailure = $_

    if ($AgentActivationStarted -and -not $AgentActivationCommitted -and $null -ne $OriginalAgentState)
    {
        $RollbackFailures = New-Object System.Collections.Generic.List[string]

        foreach ($Snapshot in $OriginalAgentState)
        {
            try
            {
                Restore-FileStateSnapshot -Snapshot $Snapshot
            }
            catch
            {
                $RollbackFailures.Add("$($Snapshot.Path): $($_.Exception.Message)")
            }
        }

        if ($RollbackFailures.Count -eq 0)
        {
            Write-Console 'Restored the previous agent files after the failed activation.' -Level 'Warning'
        }
        else
        {
            Write-Console "Agent rollback was incomplete. Use the backup directory to recover: $BackupDirectory" -Level 'Warning'
            Write-Verbose ($RollbackFailures -join [Environment]::NewLine)
        }
    }

    if ($VSCodeSettingWriteState.Attempted -and -not $AgentActivationCommitted -and $null -ne $OriginalVSCodeSettingsState)
    {
        # Restoring is only safe while the file still holds exactly what this run wrote. Anything else
        # means someone edited it afterwards, and their version outranks a stale snapshot.
        $SettingsStillOurs = $true

        if ($null -ne $VSCodeSettingWriteState.WrittenContent)
        {
            try
            {
                $SettingsStillOurs = (Read-Utf8File -Path $ResolvedVSCodeSettingsPath) -ceq $VSCodeSettingWriteState.WrittenContent
            }
            catch
            {
                $SettingsStillOurs = $false
            }
        }

        if (-not $SettingsStillOurs)
        {
            Write-Console "The VS Code settings file changed after the installer wrote it, so it was left alone. Recover the previous version from $BackupDirectory if you need it." -Level 'Warning'
        }
        else
        {
            try
            {
                Restore-FileStateSnapshot -Snapshot $OriginalVSCodeSettingsState
                Write-Console 'Restored the previous VS Code nested-subagent setting after the failed activation.' -Level 'Warning'
            }
            catch
            {
                Write-Console "Could not restore the VS Code settings file. Use the backup directory to recover: $BackupDirectory" -Level 'Warning'
            }
        }
    }

    throw $InstallFailure
}
finally
{
    Complete-InstallProgress

    if ($InstallMutexAcquired)
    {
        [void]$InstallMutex.ReleaseMutex()
    }

    if ($null -ne $InstallMutex)
    {
        $InstallMutex.Dispose()
    }
}

#endregion