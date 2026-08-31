<#
.SYNOPSIS
    Reports model identifiers referenced outside the installer's central model registry.

.DESCRIPTION
    A maintainer tool, not an end-user one. It is deliberately NOT a switch on
    Install-VSCodeCopilotCouncil-v5.ps1: that script is the single artifact people download and run,
    and every parameter added to it is permanent user-visible surface.

    Detection matches only identifiers the installer's own registry already knows, with word
    boundaries. It does not scan for vendor words. A vendor-word scan of this repository returns
    hundreds of matches from ordinary English, because "Sol" is inside "Console" and "resolve",
    "Codex" collides with nothing useful, and "Opus" appears in prose. Matching the registry instead
    of guessing at vendors is what keeps the report readable.

    PowerShell files are read through the parser so only string literals are considered, which keeps
    comments and help text out of the report. If a file will not parse, the scan falls back to a
    line match and says so.

    Report-only by default. Nothing is written unless -ApplyAliases is given, and even then only
    identifiers recorded in the installer's $ModelAliasMap are rewritten. That map ships empty, so
    -ApplyAliases is a no-op until a maintainer records a rename they have actually verified.

.PARAMETER Path
    Repository root. Defaults to the repository containing this script.

.PARAMETER IncludeChangelog
    Include CHANGELOG.md. Off by default: a changelog is meant to name models that no longer exist,
    so including it turns history into permanent noise.

.PARAMETER ApplyAliases
    Rewrite identifiers that appear in the installer's $ModelAliasMap. Writes a .bak beside each
    changed file first and prints every change. Without this switch nothing is modified.

.PARAMETER FailOnFinding
    Exit non-zero when anything actionable is reported, for use in CI.

.EXAMPLE
    .\.github\scripts\Scan-ModelReferences.ps1

.EXAMPLE
    .\.github\scripts\Scan-ModelReferences.ps1 -FailOnFinding
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [string]
    $Path,

    [Parameter()]
    [switch]
    $IncludeChangelog,

    [Parameter()]
    [switch]
    $ApplyAliases,

    [Parameter()]
    [switch]
    $FailOnFinding
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Path))
{
    $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
}

$RepositoryRoot = (Resolve-Path -LiteralPath $Path).Path
$InstallerPath = Join-Path -Path $RepositoryRoot -ChildPath 'Install-VSCodeCopilotCouncil-v5.ps1'

if (-not (Test-Path -LiteralPath $InstallerPath))
{
    throw "Installer not found under $RepositoryRoot. Pass -Path with the repository root."
}

# Reads the string literals assigned to a named script variable, without executing the installer.
function Get-AssignedStringLiteral
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Ast]
        $Ast,

        [Parameter(Mandatory = $true)]
        [string]
        $VariableName
    )

    Write-Verbose "Reading string literals assigned to `$$VariableName."

    $Assignment = $Ast.Find(
        {
            param ($Node)

            return $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $Node.Left.VariablePath.UserPath -eq $VariableName
        },
        $true)

    if ($null -eq $Assignment)
    {
        return @()
    }

    $Literals = $Assignment.Right.FindAll(
        { param ($Node) return $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] },
        $true)

    return @($Literals | ForEach-Object { $_.Value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$Tokens = $null
$ParseErrors = $null
$InstallerAst = [System.Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$Tokens, [ref]$ParseErrors)

if ($ParseErrors.Count -gt 0)
{
    throw "The installer does not parse, so its registry cannot be read: $($ParseErrors[0].Message)"
}

$RegistryNames = New-Object System.Collections.Generic.List[string]

foreach ($VariableName in @('DefaultModelCatalog', 'DefaultModels', 'RoleModelRegistry', 'ModelAliasMap', 'ModelLifecycle'))
{
    foreach ($Value in (Get-AssignedStringLiteral -Ast $InstallerAst -VariableName $VariableName))
    {
        $RegistryNames.Add($Value)
    }
}

# Longest first, so "Claude Opus 5" is reported instead of a shorter registry entry inside it.
$KnownNames = @($RegistryNames | Sort-Object -Property @{ Expression = { $_.Length } } -Descending | Select-Object -Unique)

if ($KnownNames.Count -eq 0)
{
    throw 'No model identifiers were found in the installer registry, so there is nothing to match against.'
}

$AliasSource = @(Get-AssignedStringLiteral -Ast $InstallerAst -VariableName 'ModelAliasMap')
$AliasMap = @{}

for ($Index = 0; $Index + 1 -lt $AliasSource.Count; $Index += 2)
{
    $AliasMap[$AliasSource[$Index]] = $AliasSource[$Index + 1]
}

$LifecycleNames = @(Get-AssignedStringLiteral -Ast $InstallerAst -VariableName 'ModelLifecycle')

function Get-FileClass
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $RelativePath
    )

    switch -Regex ($RelativePath)
    {
        '^Install-VSCodeCopilotCouncil-v5\.ps1$' { return 'registry' }
        '^tests[\\/]' { return 'test-fixture' }
        '^\.github[\\/]' { return 'maintainer' }
        '^README\.md$' { return 'docs-example' }
        '^CHANGELOG\.md$' { return 'historical' }
        default { return 'other' }
    }
}

$Targets = New-Object System.Collections.Generic.List[object]

$ScannedExtensions = @('.ps1', '.psd1', '.psm1', '.md', '.yml', '.yaml', '.json', '.jsonc')

foreach ($File in (Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $ScannedExtensions -contains $_.Extension.ToLowerInvariant() }))
{
    $Relative = $File.FullName.Substring($RepositoryRoot.Length).TrimStart('\', '/')

    # Anchored to a separator so this does not also swallow .github, which is where the maintainer
    # scripts and workflows live.
    if ($Relative -match '^\.git[\\/]' -or $Relative -match '^temp-' -or $Relative -match '[\\/]temp-')
    {
        continue
    }

    $Class = Get-FileClass -RelativePath $Relative

    if ($Class -eq 'historical' -and -not $IncludeChangelog)
    {
        continue
    }

    $Targets.Add([PSCustomObject]@{ Path = $File.FullName; Relative = $Relative; Class = $Class })
}

$Findings = New-Object System.Collections.Generic.List[object]

foreach ($Target in $Targets)
{
    $Content = Get-Content -LiteralPath $Target.Path -Raw -ErrorAction SilentlyContinue

    if ([string]::IsNullOrEmpty($Content))
    {
        continue
    }

    $Lines = $Content -split '\r?\n'
    $ConsideredLines = $null
    $Mode = 'text'

    if ($Target.Path -like '*.ps1')
    {
        $FileTokens = $null
        $FileErrors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($Target.Path, [ref]$FileTokens, [ref]$FileErrors)

        if ($FileErrors.Count -eq 0)
        {
            $Mode = 'ast'
            $ConsideredLines = @{}

            foreach ($Literal in $FileAst.FindAll({ param ($Node) return $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))
            {
                $ConsideredLines[$Literal.Extent.StartLineNumber] = $true
            }
        }
    }

    for ($Number = 1; $Number -le $Lines.Count; $Number++)
    {
        $Line = $Lines[$Number - 1]

        if ($Mode -eq 'ast' -and -not $ConsideredLines.ContainsKey($Number))
        {
            continue
        }

        foreach ($Name in $KnownNames)
        {
            $Pattern = '(^|[^A-Za-z0-9])' + [regex]::Escape($Name) + '([^A-Za-z0-9]|$)'

            if ($Line -cmatch $Pattern)
            {
                $Replacement = ''

                foreach ($Key in $AliasMap.Keys)
                {
                    if ([string]::Equals($Key, $Name, [System.StringComparison]::Ordinal))
                    {
                        $Replacement = [string]$AliasMap[$Key]
                    }
                }

                $Findings.Add([PSCustomObject]@{
                        File = $Target.Relative
                        Line = $Number
                        Class = $Target.Class
                        Mode = $Mode
                        Model = $Name
                        Replacement = $Replacement
                        Lifecycle = $(if ($LifecycleNames -contains $Name) { 'recorded' } else { 'none' })
                    })

                break
            }
        }
    }
}

Write-Output ''
Write-Output "Model reference scan: $RepositoryRoot"
Write-Output "Registry identifiers: $($KnownNames.Count). Files scanned: $($Targets.Count). References found: $($Findings.Count)."

if (-not $IncludeChangelog)
{
    Write-Output 'CHANGELOG.md excluded. A changelog is supposed to name retired models; pass -IncludeChangelog to see it.'
}

Write-Output ''
Write-Output 'BY FILE CLASS'

foreach ($Group in ($Findings | Group-Object -Property 'Class' | Sort-Object -Property 'Name'))
{
    Write-Output ("  {0,-14} {1}" -f $Group.Name, $Group.Count)
}

# A fixture naming a model is doing its job, and the changelog is supposed to name retired ones.
# Actionable means a reference a maintainer has to keep in step by hand, which is what the central
# registry exists to remove.
$OutsideRegistry = @($Findings | Where-Object { @('docs-example', 'maintainer', 'other') -contains $_.Class })
$FixtureCount = @($Findings | Where-Object { $_.Class -eq 'test-fixture' }).Count

Write-Output ''
Write-Output "OUTSIDE THE CENTRAL REGISTRY, ACTIONABLE ($($OutsideRegistry.Count))"

if ($OutsideRegistry.Count -eq 0)
{
    Write-Output '  none'
}
else
{
    foreach ($Finding in ($OutsideRegistry | Sort-Object -Property 'File', 'Line'))
    {
        Write-Output ("  {0}:{1}  {2}  [{3}]" -f $Finding.File, $Finding.Line, $Finding.Model, $Finding.Class)
    }
}

if ($FixtureCount -gt 0)
{
    Write-Output "  ($FixtureCount test-fixture references not listed; a fixture naming a model is not drift.)"
}

$Renameable = @($Findings | Where-Object { -not [string]::IsNullOrEmpty($_.Replacement) })

Write-Output ''
Write-Output "RECORDED RENAMES ($($Renameable.Count))"

if ($Renameable.Count -eq 0)
{
    Write-Output '  none. $ModelAliasMap is empty, so no replacement is recommended for anything.'
}
else
{
    foreach ($Finding in ($Renameable | Sort-Object -Property 'File', 'Line'))
    {
        Write-Output ("  {0}:{1}  {2} -> {3}" -f $Finding.File, $Finding.Line, $Finding.Model, $Finding.Replacement)
    }
}

$WithLifecycle = @($Findings | Where-Object { $_.Lifecycle -eq 'recorded' } | Select-Object -ExpandProperty 'Model' -Unique)

Write-Output ''
Write-Output "LIFECYCLE METADATA ($($WithLifecycle.Count) identifiers)"

if ($WithLifecycle.Count -eq 0)
{
    Write-Output '  none recorded. Unverified lifecycle facts are deliberately not shipped.'
}
else
{
    foreach ($Name in $WithLifecycle)
    {
        Write-Output "  $Name"
    }
}

if ($ApplyAliases)
{
    if ($Renameable.Count -eq 0)
    {
        Write-Output ''
        Write-Output 'Nothing to apply: no scanned reference matches a recorded rename.'
    }
    else
    {
        Write-Output ''
        Write-Output 'APPLYING RECORDED RENAMES'

        foreach ($Group in ($Renameable | Group-Object -Property 'File'))
        {
            $FullPath = Join-Path -Path $RepositoryRoot -ChildPath $Group.Name
            $Original = Get-Content -LiteralPath $FullPath -Raw
            $Updated = $Original

            foreach ($Finding in $Group.Group)
            {
                $Pattern = '(?<lead>^|[^A-Za-z0-9])' + [regex]::Escape($Finding.Model) + '(?<trail>[^A-Za-z0-9]|$)'
                $Updated = [regex]::Replace($Updated, $Pattern, { param ($Match) $Match.Groups['lead'].Value + $Finding.Replacement + $Match.Groups['trail'].Value })
            }

            if ($Updated -ne $Original)
            {
                Set-Content -LiteralPath "$FullPath.bak" -Value $Original -NoNewline
                Set-Content -LiteralPath $FullPath -Value $Updated -NoNewline
                Write-Output "  updated $($Group.Name), previous content saved to $($Group.Name).bak"
            }
        }
    }
}
else
{
    Write-Output ''
    Write-Output 'Report only. No file was modified.'
}

if ($FailOnFinding -and $OutsideRegistry.Count -gt 0)
{
    exit 1
}
