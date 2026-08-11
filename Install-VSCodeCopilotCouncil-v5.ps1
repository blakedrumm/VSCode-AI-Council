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

    Existing agent files and VS Code settings are backed up before modification.

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

    The check only reads a version string. It never downloads or runs remote code, and a failed or
    blocked check never stops the installation.

.PARAMETER NonInteractive
    Suppresses all prompts. Requires -Models, or reuses the configuration of an earlier
    installation in the target agent directory, or falls back to the built-in default pair.

.PARAMETER OpenInVSCode
    Opens the installed coordinator agent file and the VS Code settings file after
    installation when the "code" command is available.

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
        5.6.0

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
        The update check never downloads or executes remote code. It reads a version string and
        prints a link, so any upgrade stays a deliberate act by the user.

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

# The five lenses below are the hard ceiling on model count, since a sixth model would have to
# reuse a lens and two experts would then duplicate each other's work.
$MaxModelCount = 5

# The coordinator is the only agent the user ever selects. Everything else is a hidden worker.
$CoordinatorAgentName = 'Multi-Model Engineering Council'
$CoordinatorFileName = 'multi-model-engineering-council.agent.md'

# Keep this in sync with the Version entry in the .NOTES block. The update check compares it against
# the same constant in the published copy, so it is the single source of truth for the version.
$ScriptVersion = '5.6.0'

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
                Write-Verbose "Atomic replace was unavailable for $Path, so the file was written directly. $($_.Exception.Message)"
                [System.IO.File]::WriteAllText($Path, $OutputContent, $Utf8WithoutBom)
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
        Remove-Item -LiteralPath $ReplacedPath -Force -ErrorAction SilentlyContinue
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

    Write-Console "Backed up existing file: $Path"
    Write-Console "Backup copy: $BackupPath"
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

    # These characters would break the YAML front matter the agent files depend on.
    # U+0085, U+2028, and U+2029 end a line for a YAML parser but not for .NET's (?m)^ anchor, so an injected key would slip past Test-AgentFile.
    if ($Name -match '[:"''\\{}\[\]#,]' -or $Name -match '[\x00-\x1F\u0085\u2028\u2029]')
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
# Two sources are tried in order:
#   1. The GitHub releases API, which is small and fast but requires a tagged release.
#   2. The raw script file on the default branch, which works for a repository that only
#      receives plain commits.
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

    # This reads a version string and nothing else. An installer that pulls and runs remote code on
    # its own is a supply-chain risk the user never gets to review, so upgrading stays manual.
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
            Write-Verbose "No published release for $Repository. Falling back to the script header. $($_.Exception.Message)"
        }

        # A repository that only receives plain commits has no release to read, so the version is
        # taken from the constant in the published script instead.
        $Response = Invoke-WebRequest `
            -Uri "https://raw.githubusercontent.com/$Repository/HEAD/Install-VSCodeCopilotCouncil-v5.ps1" `
            -Headers @{ 'User-Agent' = 'Install-VSCodeCopilotCouncil' } `
            -UseBasicParsing `
            -TimeoutSec $TimeoutSeconds `
            -ErrorAction Stop

        # Bounded to digits and dots, so a tampered repository cannot inject anything else here.
        $VersionMatch = [regex]::Match([string]$Response.Content, '\$ScriptVersion\s*=\s*''([0-9]+(?:\.[0-9]+){1,3})''')

        if ($VersionMatch.Success)
        {
            return $VersionMatch.Groups[1].Value
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
    if ('VSCodeCouncil.Sqlite' -as [type])
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

        Add-Type -Namespace 'VSCodeCouncil' -Name 'Sqlite' -MemberDefinition @"
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

# Reads the cached model list out of one VS Code state database and returns a Name plus Category
# record for every model that is user-selectable and supports agent mode.
#
# Category is the size class VS Code publishes: powerful, versatile, or lightweight. The
# recommendation logic depends on it, because a model name alone does not reveal its size.
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

        if ([VSCodeCouncil.Sqlite]::Open([System.Text.Encoding]::UTF8.GetBytes("$TempCopy`0"), [ref]$Database, $ReadOnly, [IntPtr]::Zero) -ne 0)
        {
            return @()
        }

        foreach ($Sql in @(
                "SELECT value FROM ItemTable WHERE key='chat.cachedLanguageModels.v2'",
                "SELECT value FROM ItemTable WHERE key='chat.cachedLanguageModels'"
            ))
        {
            if ([VSCodeCouncil.Sqlite]::Prepare($Database, [System.Text.Encoding]::UTF8.GetBytes("$Sql`0"), -1, [ref]$Statement, [IntPtr]::Zero) -ne 0)
            {
                continue
            }

            $SqliteRow = 100

            if ([VSCodeCouncil.Sqlite]::Step($Statement) -eq $SqliteRow)
            {
                # SQLite documents blob-then-bytes as the safe order; the reverse can force a type conversion.
                $Blob = [VSCodeCouncil.Sqlite]::ColumnBlob($Statement, 0)
                $Length = [VSCodeCouncil.Sqlite]::ColumnBytes($Statement, 0)
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

                    $Records = New-Object System.Collections.Generic.List[object]
                    $SeenNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

                    foreach ($Record in ([System.Text.Encoding]::UTF8.GetString($Buffer) | ConvertFrom-Json))
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
                        return @($Records | Sort-Object -Property 'Name')
                    }
                }
            }

            [void][VSCodeCouncil.Sqlite]::Release($Statement)
            $Statement = [IntPtr]::Zero
        }
    }
    catch
    {
        Write-Verbose "Could not read models from $StatePath. $($_.Exception.Message)"
    }
    finally
    {
        if ($Statement -ne [IntPtr]::Zero)
        {
            [void][VSCodeCouncil.Sqlite]::Release($Statement)
        }

        if ($Database -ne [IntPtr]::Zero)
        {
            [void][VSCodeCouncil.Sqlite]::Close($Database)
        }

        Remove-Item -LiteralPath $TempCopy -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$TempCopy-wal" -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$TempCopy-shm" -Force -ErrorAction SilentlyContinue
    }

    return @()
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

        $Names = @(Get-CachedModelRecord -StatePath $StatePath)

        if ($Names.Count -gt 0)
        {
            return $Names
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
        $Lines = @(Get-Content -LiteralPath $CoordinatorPath)
    }
    catch
    {
        Write-Verbose "Could not read the previously installed coordinator agent: $($_.Exception.Message)"
        return $null
    }

    $PreviousCoordinatorModel = $null
    $SeenModels = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $PreviousModels = New-Object System.Collections.Generic.List[string]

    foreach ($Line in $Lines)
    {
        if ($null -eq $PreviousCoordinatorModel -and $Line -match '^model:\s*"(?<model>[^"]+)"\s*$')
        {
            $PreviousCoordinatorModel = $Matches['model'].Trim()
            continue
        }

        # Matches the roster line this installer writes: "- <Model> Expert running <Model>, primary lens <Lens>".
        if ($Line -match '^-\s.+\sExpert\srunning\s(?<model>[^,]+),\sprimary\slens\s.+$')
        {
            $Candidate = $Matches['model'].Trim()

            if ((Test-ModelName -Name $Candidate) -and $SeenModels.Add($Candidate))
            {
                $PreviousModels.Add($Candidate)
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

    $Minor = 0

    if ($Match.Groups[2].Success)
    {
        $Minor = [int]$Match.Groups[2].Value
    }

    return [version]::new([int]$Match.Groups[1].Value, $Minor)
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

    $Candidates = @(
        $Catalog |
            Where-Object { (Test-ModelName -Name $_) -and $_ -notmatch '(?i)^auto$' } |
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
            elseif ($Token -eq 'c')
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
        $BackupDirectory
    )

    $SettingsDirectory = Split-Path -Path $SettingsPath -Parent

    if (-not (Test-Path -LiteralPath $SettingsDirectory))
    {
        New-Item -Path $SettingsDirectory -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $SettingsPath))
    {
        Write-Utf8File -Path $SettingsPath -Content '{}'
        Write-Console "Created VS Code settings file: $SettingsPath"
    }
    else
    {
        Backup-ExistingFile -Path $SettingsPath -BackupDirectory $BackupDirectory
    }

    $Content = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8)

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

    # Match against the comment-masked copy so a commented-out setting is never edited in place.
    # Masking preserves length, so every offset taken from $Masked maps onto $Content unchanged.
    $Masked = ConvertTo-CommentMaskedJson -Text $Content
    $SettingMatch = [regex]::Match($Masked, '"' + [regex]::Escape($SettingName) + '"\s*:\s*(true|false)')

    if ($SettingMatch.Success)
    {
        $ValueGroup = $SettingMatch.Groups[1]
        $UpdatedContent = $Content.Remove($ValueGroup.Index, $ValueGroup.Length).Insert($ValueGroup.Index, 'true')
    }
    elseif ([regex]::IsMatch($Masked, '"' + [regex]::Escape($SettingName) + '"\s*:'))
    {
        # The key exists with something other than true/false. Inserting a second copy would create a duplicate key.
        throw "$SettingName already exists in $SettingsPath with a value that is not true or false. Correct it by hand, then re-run."
    }
    else
    {
        $OpenBraceIndex = $Masked.IndexOf([char]'{')

        if ($OpenBraceIndex -lt 0)
        {
            throw "VS Code settings file does not appear to contain a root JSON object: $SettingsPath"
        }

        # Inserting always beats rebuilding the object, because rebuilding would discard the user's comments.
        # A root object holding nothing but whitespace or comments must not gain a trailing comma.
        $Separator = ''

        if ($Masked.Substring($OpenBraceIndex + 1) -match '[^\s}]')
        {
            $Separator = ','
        }

        $SettingLine = $NewLine + "  `"$SettingName`": true$Separator" + $NewLine
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

    # PreserveLineEndings keeps the user's existing CRLF or LF style instead of rewriting the whole file.
    Write-Utf8File -Path $SettingsPath -Content $UpdatedContent -PreserveLineEndings

    try
    {
        $WrittenSettings = ConvertFrom-JsoncText -Text ([System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8))
    }
    catch
    {
        throw "Updating $SettingsPath produced invalid JSON. A backup was written to $BackupDirectory. $($_.Exception.Message)"
    }

    if ((Get-PropertyValue -InputObject $WrittenSettings -Name $SettingName) -ne $true)
    {
        throw "Failed to verify $SettingName=true in $SettingsPath"
    }

    Write-Console "Enabled VS Code setting: $SettingName = true"
    Write-Console "VS Code settings file: $SettingsPath"
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
# user-invocable false hides an agent from the picker, and disable-model-invocation true stops
# unrelated agents from recruiting it. Together they keep the workers hidden but reachable by the
# coordinator, which lists them explicitly in its own agents property.
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
    $Lines.Add('disable-model-invocation: true')
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
        -Tools @('read', 'search', 'web')

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

1. Repository source code
2. Reproducible tests
3. Runtime, compiler, or interpreter behavior
4. Official documentation
5. API specifications
6. Platform behavior and logs
7. Logical consistency
8. Established engineering practice

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
        -Tools @('agent', 'read', 'search', 'web') `
        -Agents $ReviewerNames

    $FocusBlock = ($LensFocus | ForEach-Object { "- $_" }) -join "`n"
    $ReviewerBlock = ($ReviewerNames | ForEach-Object { "- $_" }) -join "`n"

    if ($CrossModelReview)
    {
        $ReviewerIntro = 'Each of these reviewers runs a different model than you do, so the critique is genuinely independent.'
    }
    else
    {
        $ReviewerIntro = 'Only one model is configured, so this reviewer runs the same model with a fresh context. Treat it as a blind-spot check, not as an independent model.'
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

Use the nested review only when the coordinator allows it for this branch, and at least one of these is true:

- your conclusion is high impact or hard to reverse
- a critical assumption is unverified and you cannot verify it with a tool
- security, data integrity, or shared behavior is at stake
- the evidence is thin or conflicting

If the coordinator told you to skip nested review, skip it. Otherwise skip it by default. A nested review roughly doubles the cost of your branch.

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

Prefer repository source code, reproducible tests, and observed runtime behavior over documentation, specifications, or convention. Confidence is not evidence. Model agreement is not evidence.

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
        -Tools @('agent', 'read', 'search', 'edit', 'execute', 'web', 'todos') `
        -Agents $ExpertNames

    $RosterBlock = ($ExpertMap | ForEach-Object {
            "- $($_.ExpertName) running $($_.ModelName), primary lens $($_.LensTitle)"
        }) -join "`n"

    $ReviewBlock = ($ExpertMap | ForEach-Object {
            "- $($_.ExpertName) may consult one of: $($_.ReviewerNames -join ', ')"
        }) -join "`n"

    $ExpertCount = $ExpertMap.Count

    if ($CrossModelReview)
    {
        $Tier3Note = 'Run two experts on different models in parallel and instruct each to spend its one nested peer-review call attacking its own strongest assumption.'
    }
    else
    {
        $Tier3Note = 'Only one model is configured, so a true cross-model debate is not possible. Run the single expert twice with opposing framings, once to defend the proposal and once to break it, then adjudicate yourself.'
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

### Tier 2 - Two experts in parallel

Use when:

- at least two models are configured, and
- the task spans two lenses, and
- there is a real design or implementation choice to make, or the change touches shared code or public behavior

Invoke both experts in the same turn with distinct, non-overlapping scopes, then synthesize. Cost: two parallel expert calls.

### Tier 3 - Adversarial debate

Use ONLY when at least one of these is true:

- the user explicitly asked for a debate, a second opinion, or adversarial review
- Tier 1 or Tier 2 produced a material disagreement you could not settle with a tool
- the decision is hard to reverse and no available tool can falsify either position

A disagreement you can settle by reading a file or running a command is not a Tier 3 trigger. Settle it yourself.

$Tier3Note

Cost: two expert calls plus their nested reviews, so roughly four model invocations.

### Tier 4 - Parallel engineering team

Use ONLY when at least two models are configured and at least one of these is true:

- the user explicitly asked for the full team or a complete review
- the work spans several genuinely independent subsystems that need different lenses at once
- a difficult bug has already survived a Tier 1 or Tier 2 attempt

Breadth of files alone is not a Tier 4 trigger. A large but uniform change is Tier 1 or Tier 2.

Fan out one expert per configured model, each with its own lens and its own scope. Cost: up to $ExpertCount parallel expert calls, and up to double that if you also authorize nested review.

### Tier 5 - Unconstrained brainstorming

Use ONLY when the user explicitly asks for it. The request must contain a word such as "brainstorm", "deep review", or "unconstrained". Nothing else triggers this tier. Do not infer it from a large task, a vague task, or a request to be thorough.

Dispatch the full parallel team exactly as in Tier 4, one expert per configured model with its own lens and its own scope. The difference is the brief, not the roster.

Append this override verbatim to EVERY delegation brief you send in this tier:

    This is a Tier 5 brainstorm. Ignore your standard 8-line brevity limits. Provide a comprehensive, unconstrained, and exhaustive review of all potential improvements, edge cases, and cross-domain enhancements you can find.

The lens assignment and the out-of-scope list still apply. Unconstrained means unconstrained in length and depth, not permission for two experts to investigate the same thing.

Cost: up to $ExpertCount parallel expert calls, each returning a long report. This is the most expensive tier by a wide margin. Never select it on your own initiative.

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

Tell an expert to use its one nested review only when the branch meets the Tier 3 conditions. Otherwise tell it explicitly to skip nested review.

## Disagreement resolution

1. Repository source code
2. Reproducible tests
3. Runtime, compiler, or interpreter behavior
4. Official documentation
5. API specifications
6. Platform diagnostics and logs
7. Logical consistency
8. Established engineering practice

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
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string]
        $ExpectedName,

        [Parameter(Mandatory = $true)]
        [string]
        $ExpectedModel,

        [Parameter(Mandatory = $true)]
        [bool]
        $ExpectedUserInvocable,

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

    if (-not (Test-Path -LiteralPath $Path))
    {
        throw "Agent validation failed because the file does not exist: $Path"
    }

    $Content = Get-Content -LiteralPath $Path -Raw

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

#endregion

#region 13. Environment detection

# Reads VS Code state from disk first. The equivalent CLI calls cost roughly 700 ms because each
# one starts a new Electron process, and the result is only used for informational output.
function Get-VSCodeStatus
{
    $Result = [ordered]@{
        CodeCommand = $null
        Version = $null
        CopilotInstalled = $false
        CopilotChatInstalled = $false
    }

    # CommandType Application keeps a shell alias or function named 'code' from being picked up.
    # Select-Object is required because the shim ships as both code.cmd and an extensionless code.
    $CodeCommand = Get-Command -Name 'code' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $CodeCommand)
    {
        $Result.CodeCommand = $CodeCommand.Source
    }

    $CandidateRoots = New-Object System.Collections.Generic.List[string]

    if ($null -ne $CodeCommand -and -not [string]::IsNullOrWhiteSpace($CodeCommand.Source))
    {
        # code.cmd sits in <install root>\bin, so the install root is its grandparent.
        $BinDirectory = Split-Path -Path $CodeCommand.Source -Parent

        if (-not [string]::IsNullOrWhiteSpace($BinDirectory))
        {
            $CodeRoot = Split-Path -Path $BinDirectory -Parent

            if (-not [string]::IsNullOrWhiteSpace($CodeRoot))
            {
                [void]$CandidateRoots.Add($CodeRoot)
            }
        }
    }

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
                $PackageJson = Get-Content -LiteralPath $PackageJsonPath -Raw | ConvertFrom-Json
                $Version = [string](Get-PropertyValue -InputObject $PackageJson -Name 'version')

                if (-not [string]::IsNullOrWhiteSpace($Version))
                {
                    $Result.Version = $Version
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
            foreach ($Entry in @(Get-Content -LiteralPath $ExtensionsJsonPath -Raw | ConvertFrom-Json))
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
    elseif ($null -ne $CodeCommand)
    {
        try
        {
            $Extensions = @(& $CodeCommand.Source --list-extensions 2>$null)
            $Result.CopilotInstalled = $Extensions -contains 'GitHub.copilot'
            $Result.CopilotChatInstalled = $Extensions -contains 'GitHub.copilot-chat'
        }
        catch
        {
            $Result.CopilotInstalled = $false
            $Result.CopilotChatInstalled = $false
        }
    }

    if ([string]::IsNullOrWhiteSpace($Result.Version) -and $null -ne $CodeCommand)
    {
        try
        {
            $VersionOutput = @(& $CodeCommand.Source --version 2>$null)

            if ($VersionOutput.Count -gt 0)
            {
                $Result.Version = $VersionOutput[0]
            }
        }
        catch
        {
            $Result.Version = $null
        }
    }

    return [PSCustomObject]$Result
}

#endregion

#region 14. Installation
#
# Execution starts here. Everything above this point only defined functions and constants.

$InstallTimer = [System.Diagnostics.Stopwatch]::StartNew()

# UserInteractive is checked as well as -NonInteractive, because a scheduled task or a build agent
# has no console to prompt on and Read-Host would hang there forever.
$AllowPrompts = (-not $NonInteractive) -and [Environment]::UserInteractive
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
    Set-VSCodeNestedSubagentsSetting -SettingsPath $ResolvedVSCodeSettingsPath -BackupDirectory $BackupDirectory

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
        # Ordinal, because Select-Object -Unique is case-sensitive and can leave two spellings of
        # one model in the list. A case-insensitive match would then exclude both and yield nothing.
        $PeerReviewers = @($ExpertMap |
                Where-Object { -not [string]::Equals($_.ModelName, $Expert.ModelName, [System.StringComparison]::Ordinal) } |
                ForEach-Object { $_.ReviewerName })

        if ($PeerReviewers.Count -gt 0)
        {
            $Expert.ReviewerNames = $PeerReviewers
        }
        else
        {
            $Expert.ReviewerNames = @($Expert.ReviewerName)
        }
    }
    else
    {
        $Expert.ReviewerNames = @($Expert.ReviewerName)
    }
}

# Generate and write every agent file. Reviewers are written before their expert so the file the
# expert references already exists on disk.
foreach ($Expert in $ExpertMap)
{
    $ReviewerContent = New-ReviewerAgentContent -AgentName $Expert.ReviewerName -ModelName $Expert.ModelName
    Install-AgentFile -AgentDirectory $AgentDirectory -FileName $Expert.ReviewerFile -Content $ReviewerContent -BackupDirectory $BackupDirectory

    $ExpertContent = New-ExpertAgentContent `
        -AgentName $Expert.ExpertName `
        -ModelName $Expert.ModelName `
        -LensTitle $Expert.LensTitle `
        -LensFocus $Expert.LensFocus `
        -ReviewerNames $Expert.ReviewerNames `
        -CoordinatorName $CoordinatorAgentName `
        -CrossModelReview $CrossModelReview

    Install-AgentFile -AgentDirectory $AgentDirectory -FileName $Expert.ExpertFile -Content $ExpertContent -BackupDirectory $BackupDirectory
}

$CoordinatorContent = New-CoordinatorAgentContent `
    -AgentName $CoordinatorAgentName `
    -ModelName $ResolvedCoordinatorModel `
    -ExpertMap $ExpertMap.ToArray() `
    -CrossModelReview $CrossModelReview

Install-AgentFile -AgentDirectory $AgentDirectory -FileName $CoordinatorFileName -Content $CoordinatorContent -BackupDirectory $BackupDirectory

# A previous run with different models would otherwise leave experts the coordinator no longer lists.
$CurrentAgentFiles = New-Object System.Collections.Generic.HashSet[string]

foreach ($Expert in $ExpertMap)
{
    [void]$CurrentAgentFiles.Add($Expert.ExpertFile)
    [void]$CurrentAgentFiles.Add($Expert.ReviewerFile)
}

$StaleAgentFiles = @(Get-ChildItem -LiteralPath $AgentDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^mm-(expert|reviewer)-.+\.agent\.md$' -and -not $CurrentAgentFiles.Contains($_.Name) })

foreach ($StaleFile in $StaleAgentFiles)
{
    Backup-ExistingFile -Path $StaleFile.FullName -BackupDirectory $BackupDirectory
    Remove-Item -LiteralPath $StaleFile.FullName -Force
    Write-Console "Removed agent file left over from a previous configuration: $($StaleFile.Name)"
}

Complete-InstallStep

Start-InstallStep -Name 'Validate agent files'

# Read back everything just written and prove it is structurally sound. A broken agent file loads
# without complaint in VS Code and simply misbehaves, so this is the only place the problem
# becomes visible.
foreach ($Expert in $ExpertMap)
{
    Test-AgentFile `
        -Path (Join-Path -Path $AgentDirectory -ChildPath $Expert.ReviewerFile) `
        -ExpectedName $Expert.ReviewerName `
        -ExpectedModel $Expert.ModelName `
        -ExpectedUserInvocable $false `
        -MustNotDelegate

    Test-AgentFile `
        -Path (Join-Path -Path $AgentDirectory -ChildPath $Expert.ExpertFile) `
        -ExpectedName $Expert.ExpertName `
        -ExpectedModel $Expert.ModelName `
        -ExpectedUserInvocable $false `
        -ExpectedAgents $Expert.ReviewerNames `
        -MustNotSelfReview:$CrossModelReview
}

Test-AgentFile `
    -Path (Join-Path -Path $AgentDirectory -ChildPath $CoordinatorFileName) `
    -ExpectedName $CoordinatorAgentName `
    -ExpectedModel $ResolvedCoordinatorModel `
    -ExpectedUserInvocable $true `
    -ExpectedAgents @($ExpertMap | ForEach-Object { $_.ExpertName })

Write-Console 'All agent files passed post-install validation.'

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

        & $VSCodeStatus.CodeCommand --reuse-window (Join-Path -Path $AgentDirectory -ChildPath $CoordinatorFileName)

        if (-not [string]::IsNullOrWhiteSpace($ResolvedVSCodeSettingsPath))
        {
            & $VSCodeStatus.CodeCommand --reuse-window $ResolvedVSCodeSettingsPath
        }
    }
    else
    {
        Write-Console 'The VS Code CLI is not available in PATH, so files were not opened automatically.'
    }
}

#endregion