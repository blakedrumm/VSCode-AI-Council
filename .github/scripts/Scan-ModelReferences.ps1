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

function Read-ReferenceFile
{
    param ([Parameter(Mandatory = $true)][string]$LiteralPath)

    $Bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $HasBom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    $Offset = if ($HasBom) { 3 } else { 0 }
    $Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

    return [PSCustomObject]@{
        Bytes = $Bytes
        Content = $Utf8.GetString($Bytes, $Offset, $Bytes.Length - $Offset)
        HasBom = $HasBom
    }
}

$Tokens = $null
$ParseErrors = $null
$InstallerSnapshot = Read-ReferenceFile -LiteralPath $InstallerPath
$InstallerAst = [System.Management.Automation.Language.Parser]::ParseInput($InstallerSnapshot.Content, [ref]$Tokens, [ref]$ParseErrors)

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

$NamePattern = '(?<![A-Za-z0-9])(?:' + (($KnownNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![A-Za-z0-9])'
$NameMatcher = New-Object System.Text.RegularExpressions.Regex($NamePattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
$AliasMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
$AliasAssignment = $InstallerAst.Find({
    param ($Node)
    $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $Node.Left.VariablePath.UserPath -eq 'ModelAliasMap'
}, $true)

if ($null -ne $AliasAssignment)
{
    $AliasLiteral = $AliasAssignment.Right.Find({ param ($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $true)

    if ($null -eq $AliasLiteral)
    {
        throw 'ModelAliasMap must be a literal hashtable; the scanner never executes registry expressions.'
    }

    foreach ($Entry in $AliasLiteral.SafeGetValue().GetEnumerator())
    {
        if ($Entry.Key -isnot [string] -or $Entry.Value -isnot [string] -or
            [string]::IsNullOrWhiteSpace($Entry.Key) -or [string]::IsNullOrWhiteSpace($Entry.Value))
        {
            throw 'ModelAliasMap must contain nonempty string names and replacements.'
        }

        $AliasMap[$Entry.Key] = $Entry.Value
    }
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

$Directories = New-Object System.Collections.Generic.Stack[string]
$Directories.Push($RepositoryRoot)

while ($Directories.Count -gt 0)
{
    foreach ($File in (Get-ChildItem -LiteralPath $Directories.Pop() -ErrorAction SilentlyContinue))
    {
        if ($File.Name -eq '.git' -or $File.Name -like 'temp-*' -or
            $File.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
        {
            continue
        }

        if ($File.PSIsContainer)
        {
            $Directories.Push($File.FullName)
            continue
        }

        if ($ScannedExtensions -notcontains $File.Extension.ToLowerInvariant())
        {
            continue
        }

        $Relative = $File.FullName.Substring($RepositoryRoot.Length).TrimStart('\', '/')
        $Class = Get-FileClass -RelativePath $Relative

        if ($Class -eq 'historical' -and -not $IncludeChangelog)
        {
            continue
        }

        $Targets.Add([PSCustomObject]@{ Path = $File.FullName; Relative = $Relative; Class = $Class })
    }
}

$Findings = New-Object System.Collections.Generic.List[object]
$FileStates = @{}

foreach ($Target in $Targets)
{
    try
    {
        $Snapshot = if ($Target.Class -eq 'registry') { $InstallerSnapshot } else { Read-ReferenceFile -LiteralPath $Target.Path }
    }
    catch
    {
        Write-Warning "Skipped unreadable or invalid UTF-8 file: $($Target.Relative). $($_.Exception.Message)"
        continue
    }

    $Content = $Snapshot.Content

    if ([string]::IsNullOrEmpty($Content))
    {
        continue
    }

    $Literals = @()
    $Mode = 'text'
    $IsPowerShell = @('.ps1', '.psm1', '.psd1') -contains [System.IO.Path]::GetExtension($Target.Path)

    if ($IsPowerShell)
    {
        $FileTokens = $null
        $FileErrors = @()
        $FileAst = if ($Target.Class -eq 'registry') { $InstallerAst } else {
            [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$FileTokens, [ref]$FileErrors)
        }

        if ($FileErrors.Count -eq 0)
        {
            $Mode = 'ast'
            $Literals = @($FileAst.FindAll({
                param ($Node)
                $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    -not ($Node.Parent -is [System.Management.Automation.Language.CommandAst] -and $Node.Parent.CommandElements[0] -eq $Node)
            }, $true))
        }
    }

    $FileStates[$Target.Relative] = @{
        Snapshot = $Snapshot; Literals = $Literals; IsPowerShell = $IsPowerShell; Mode = $Mode
    }
    $Regions = if ($Mode -eq 'ast') {
        @($Literals | ForEach-Object { [PSCustomObject]@{ Offset = $_.Extent.StartOffset; Text = $_.Extent.Text } })
    } else {
        @([PSCustomObject]@{ Offset = 0; Text = $Content })
    }
    [int[]]$LineStarts = @(0) + @([regex]::Matches($Content, '\n') | ForEach-Object { $_.Index + 1 })

    foreach ($Region in $Regions)
    {
        foreach ($Match in $NameMatcher.Matches($Region.Text))
        {
            $Name = $Match.Value
            $Offset = $Region.Offset + $Match.Index
            $LineIndex = [System.Array]::BinarySearch([array]$LineStarts, [object]$Offset)
            if ($LineIndex -lt 0)
            {
                $LineIndex = (-bnot $LineIndex) - 1
            }

            $Findings.Add([PSCustomObject]@{
                    File = $Target.Relative
                    Line = $LineIndex + 1
                    Class = $Target.Class
                    Mode = $Mode
                    Model = $Name
                    Replacement = $(if ($AliasMap.ContainsKey($Name)) { $AliasMap[$Name] } else { '' })
                    Lifecycle = $(if ($LifecycleNames -contains $Name) { 'recorded' } else { 'none' })
                })
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

$Renameable = @($Findings | Where-Object { $_.Class -ne 'registry' -and -not [string]::IsNullOrEmpty($_.Replacement) })

Write-Output ''
Write-Output "RECORDED RENAMES ($($Renameable.Count))"

if ($Renameable.Count -eq 0)
{
    Write-Output '  none. No references outside the registry match a recorded rename.'
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

        foreach ($Finding in $Renameable)
        {
            $State = $FileStates[$Finding.File]
            if ($State.IsPowerShell -and $State.Mode -ne 'ast')
            {
                throw "PowerShell file does not parse, so aliases were not applied: $($Finding.File)"
            }
        }

        $ReplaceAlias = [System.Text.RegularExpressions.MatchEvaluator]{
            param ($Match)
            if ($AliasMap.ContainsKey($Match.Value)) { return $AliasMap[$Match.Value] }
            return $Match.Value
        }

        foreach ($Group in ($Renameable | Group-Object -Property 'File'))
        {
            $FullPath = Join-Path -Path $RepositoryRoot -ChildPath $Group.Name
            $State = $FileStates[$Group.Name]
            $Original = $State.Snapshot.Content
            $Updated = $Original

            if ($State.IsPowerShell)
            {
                foreach ($Literal in ($State.Literals | Sort-Object -Property { $_.Extent.StartOffset } -Descending))
                {
                    $Value = $NameMatcher.Replace($Literal.Value, $ReplaceAlias)
                    if ($Value -ceq $Literal.Value) { continue }

                    $Encoded = "'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
                    $Updated = $Updated.Remove($Literal.Extent.StartOffset, $Literal.Extent.EndOffset - $Literal.Extent.StartOffset).Insert($Literal.Extent.StartOffset, $Encoded)
                }
            }
            else
            {
                $Updated = $NameMatcher.Replace($Original, $ReplaceAlias)
            }

            if ($Updated -cne $Original)
            {
                if (-not [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
                    [System.IO.File]::ReadAllBytes($FullPath), $State.Snapshot.Bytes))
                {
                    throw "File changed during the scan and was not overwritten: $($Group.Name)"
                }

                $BackupPath = "$FullPath.bak"
                if (Test-Path -LiteralPath $BackupPath)
                {
                    $BackupPath = "$FullPath.$([guid]::NewGuid().ToString('N')).bak"
                }
                [System.IO.File]::Copy($FullPath, $BackupPath, $false)

                [byte[]]$UpdatedBytes = (New-Object System.Text.UTF8Encoding($false, $true)).GetBytes($Updated)
                if ($State.Snapshot.HasBom) { $UpdatedBytes = [byte[]](0xEF, 0xBB, 0xBF) + $UpdatedBytes }
                $TemporaryPath = "$FullPath.$([guid]::NewGuid().ToString('N')).tmp"

                try
                {
                    [System.IO.File]::WriteAllBytes($TemporaryPath, $UpdatedBytes)
                    if (-not [System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
                        [System.IO.File]::ReadAllBytes($FullPath), $State.Snapshot.Bytes))
                    {
                        throw "File changed before replacement and was not overwritten: $($Group.Name)"
                    }
                    [System.IO.File]::Replace($TemporaryPath, $FullPath, [System.Management.Automation.Language.NullString]::Value, $true)
                }
                finally
                {
                    Remove-Item -LiteralPath $TemporaryPath -Force -ErrorAction SilentlyContinue
                }

                Write-Output "  updated $($Group.Name), previous content saved to $(Split-Path -Path $BackupPath -Leaf)"
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
