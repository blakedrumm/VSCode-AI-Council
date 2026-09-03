#Requires -Version 5.1
<#
.SYNOPSIS
    Refreshes or verifies the checked-in model recommendation review.

.DESCRIPTION
    Runs the installer's shipping model discovery and recommendation functions against this
    machine's live VS Code cache. It installs nothing and does not change VS Code settings.

    Without -Update, this is a read-only pre-push gate. Every run re-derives the recommendation from
    the live cache, so a push is blocked when the checked-in reference, the installer, or the README
    disagrees with what this profile actually offers today.

    The gate deliberately does not require the stamped date to be today. Agreement with the live
    cache is what proves the recommendation current; the date only records when the result last
    changed. Re-running on a later day therefore re-verifies the same finding and passes.

    With -Update, it refreshes .github/model-recommendation-review.json, the installer review date,
    and the marked README example, but only when the recommendation actually changed. Run it only
    from the designated high-access profile. Other users can have smaller catalogs, and their result
    must not replace the reference.

.PARAMETER Path
    Repository root. Defaults to the repository containing this script.

.PARAMETER ReviewDate
    Date recorded when the recommendation changed. Defaults to today. An unchanged recommendation
    keeps the date already on record rather than being restamped.

.PARAMETER Update
    Write the live review into the tracked representations, if and only if the recommendation
    changed. Without this switch nothing is written.

.PARAMETER AllowReferenceContraction
    With -Update, explicitly permits a smaller catalog or the disappearance of a previously
    recommended model. Use only after confirming the designated profile really lost that model;
    without this acknowledgement a lower-access or stale profile cannot replace the reference.

.EXAMPLE
    .\.github\scripts\Update-ModelRecommendation.ps1 -Update

.EXAMPLE
    .\.github\scripts\Update-ModelRecommendation.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param
(
    [Parameter()]
    [string]
    $Path,

    [Parameter()]
    [datetime]
    $ReviewDate = (Get-Date).Date,

    [Parameter()]
    [switch]
    $Update,

    [Parameter()]
    [switch]
    $AllowReferenceContraction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Path))
{
    $Path = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
}

$RepositoryRoot = (Resolve-Path -LiteralPath $Path).Path
$InstallerPath = Join-Path -Path $RepositoryRoot -ChildPath 'Install-VSCodeCopilotCouncil-v5.ps1'
$ReadmePath = Join-Path -Path $RepositoryRoot -ChildPath 'README.md'
$ReviewPath = Join-Path -Path $RepositoryRoot -ChildPath '.github\model-recommendation-review.json'

if ($AllowReferenceContraction -and -not $Update)
{
    throw '-AllowReferenceContraction is only valid together with -Update.'
}

foreach ($RequiredPath in @($InstallerPath, $ReadmePath))
{
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf))
    {
        throw "Required repository file not found: $RequiredPath"
    }
}

function Set-Utf8FileContent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $LiteralPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $Content
    )

    $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $Utf8WithoutBom)
}

function Get-AssignmentStatement
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

    $Assignments = @($Ast.FindAll(
            {
                param ($Node)

                return $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.Left.VariablePath.UserPath -eq $VariableName
            },
            $true))

    if ($Assignments.Count -ne 1)
    {
        throw "Expected one assignment of `$$VariableName in the installer, found $($Assignments.Count)."
    }

    return $Assignments[0]
}

function Get-OrdinalDateText
{
    param
    (
        [Parameter(Mandatory = $true)]
        [datetime]
        $Date
    )

    $Suffix = 'th'

    if ($Date.Day -lt 11 -or $Date.Day -gt 13)
    {
        switch ($Date.Day % 10)
        {
            1 { $Suffix = 'st' }
            2 { $Suffix = 'nd' }
            3 { $Suffix = 'rd' }
        }
    }

    return ('{0} {1}{2}, {3}' -f
        $Date.ToString('MMMM', [System.Globalization.CultureInfo]::InvariantCulture),
        $Date.Day,
        $Suffix,
        $Date.Year)
}

$InstallerText = [System.IO.File]::ReadAllText($InstallerPath)
$Tokens = $null
$ParseErrors = $null
$InstallerAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $InstallerPath,
    [ref]$Tokens,
    [ref]$ParseErrors)

if ($ParseErrors.Count -gt 0)
{
    throw "The installer does not parse, so its recommendation cannot be reviewed: $($ParseErrors[0].Message)"
}

$FunctionDefinitions = $InstallerAst.FindAll(
    { param ($Node) return $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $true)

foreach ($FunctionName in @(
        'Write-Console',
        'Get-PropertyValue',
        'Test-ModelName',
        'Test-PreviewModelName',
        'ConvertFrom-ModelCacheJson',
        'ConvertTo-OrdinalModelRecord',
        'Initialize-SqliteInterop',
        'Get-CachedModelRecord',
        'Get-VSCodeModelCatalog',
        'Get-ModelFamily',
        'Get-ModelTierWeight',
        'Get-ModelVersion',
        'Get-RecommendedModelSet'
    ))
{
    $Definition = @($FunctionDefinitions | Where-Object { $_.Name -eq $FunctionName })

    if ($Definition.Count -ne 1)
    {
        throw "Expected one definition of $FunctionName in the installer, found $($Definition.Count)."
    }

    . ([scriptblock]::Create($Definition[0].Extent.Text))
}

foreach ($VariableName in @('LensCatalog', 'DefaultModelCatalog', 'DefaultModelCategoryMap'))
{
    $Assignment = Get-AssignmentStatement -Ast $InstallerAst -VariableName $VariableName
    . ([scriptblock]::Create($Assignment.Extent.Text))
}

$MaximumCount = $LensCatalog.Count

# WhatIf must still discover enough state to describe the proposed tracked-file update. The
# shipping reader copies VS Code's locked database to a random temp path before opening it, and a
# propagated WhatIf would suppress that disposable snapshot and make discovery falsely return no
# models. Restore the caller's preference before ShouldProcess decides whether tracked files move.
$CallerWhatIfPreference = $WhatIfPreference

try
{
    $WhatIfPreference = $false
    $Records = @(Get-VSCodeModelCatalog)
}
finally
{
    $WhatIfPreference = $CallerWhatIfPreference
}

if ($Records.Count -eq 0)
{
    throw 'No agent-capable model records were read from the VS Code cache. Nothing was updated or verified.'
}

$ExistingReview = $null
$ExistingReviewJson = $null
$ExistingReviewProblem = $null

if (Test-Path -LiteralPath $ReviewPath -PathType Leaf)
{
    try
    {
        $ExistingReviewJson = [System.IO.File]::ReadAllText($ReviewPath)
        $ExistingReview = $ExistingReviewJson | ConvertFrom-Json
    }
    catch
    {
        if ($Update)
        {
            throw "The existing recommendation review cannot be parsed, so it will not be overwritten: $($_.Exception.Message)"
        }

        $ExistingReviewProblem = "the checked-in review could not be read: $($_.Exception.Message)"
    }
}
else
{
    $ExistingReviewProblem = 'the checked-in review file is missing'
}

if ($Update -and $null -ne $ExistingReview)
{
    $PreviousCatalog = @(Get-PropertyValue -InputObject $ExistingReview -Name 'catalog')
    $PreviousRecommended = @(Get-PropertyValue -InputObject $ExistingReview -Name 'recommended')
    $CurrentNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Record in $Records) { [void]$CurrentNames.Add($Record.Name) }

    $MissingPreviousRecommendations = @($PreviousRecommended | Where-Object { -not $CurrentNames.Contains($_) })
    $ReferenceContracted = $Records.Count -lt $PreviousCatalog.Count -or $MissingPreviousRecommendations.Count -gt 0

    if ($ReferenceContracted -and -not $AllowReferenceContraction)
    {
        $MissingText = if ($MissingPreviousRecommendations.Count -gt 0)
        {
            " Previously recommended models now missing: $($MissingPreviousRecommendations -join ', ')."
        }
        else
        {
            ''
        }

        throw "The live catalog contracted from $($PreviousCatalog.Count) to $($Records.Count) records.$MissingText Refusing to replace the high-access reference. Confirm this is a real catalog change, then re-run with -Update -AllowReferenceContraction."
    }
}

$CategoryMap = @{}
$PreviewMap = @{}

foreach ($Record in $Records)
{
    $CategoryMap[$Record.Name] = $Record.Category
    $PreviewMap[$Record.Name] = $Record.IsPreview
}

$Catalog = @($Records | ForEach-Object { $_.Name })
$Recommended = @(Get-RecommendedModelSet `
        -Catalog $Catalog `
        -MaximumCount $MaximumCount `
        -CategoryMap $CategoryMap `
        -PreviewMap $PreviewMap)

if ($Recommended.Count -ne $MaximumCount)
{
    throw "This profile produced $($Recommended.Count) recommendation(s) for $MaximumCount seats. Use the designated high-access profile before updating the public reference."
}

foreach ($Name in $Recommended)
{
    $Record = @($Records | Where-Object { $_.Name -ceq $Name })[0]

    if ($Name -match '(?i)^auto$|internal[\s\-]*only' -or
        $Record.Category -eq 'lightweight')
    {
        throw "The shipping algorithm recommended an ineligible reference model: $Name. Inspect the ranking before updating anything."
    }

    if ($DefaultModelCatalog -notcontains $Name -or
        -not $DefaultModelCategoryMap.ContainsKey($Name) -or
        $DefaultModelCategoryMap[$Name] -ne $Record.Category)
    {
        throw "The built-in fallback does not carry the reviewed name and category for $Name. Update the fallback deliberately, then run this command again."
    }
}

$FallbackRecommendation = @(Get-RecommendedModelSet `
        -Catalog $DefaultModelCatalog `
        -MaximumCount $MaximumCount `
        -CategoryMap $DefaultModelCategoryMap `
        -PreviewMap @{})

if (($FallbackRecommendation -join "`n") -cne ($Recommended -join "`n"))
{
    throw "The built-in fallback recommends '$($FallbackRecommendation -join ', ')' instead of the reviewed live set '$($Recommended -join ', ')'. Update it deliberately before continuing."
}

$LiveCatalogRows = @($Records | ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.Category, [bool]$_.IsPreview })
$ExistingCatalogRows = @()
$ExistingRecommended = @()
$ExistingReviewDate = $null

if ($null -ne $ExistingReview)
{
    # Read through Get-PropertyValue rather than dot notation: this file is hand-editable, and a
    # missing key would otherwise throw a raw property error instead of a reportable problem.
    $ExistingCatalogRows = @(@(Get-PropertyValue -InputObject $ExistingReview -Name 'catalog') |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                '{0}|{1}|{2}' -f (Get-PropertyValue -InputObject $_ -Name 'name'),
                    (Get-PropertyValue -InputObject $_ -Name 'category'),
                    [bool](Get-PropertyValue -InputObject $_ -Name 'isPreview')
            })
    $ExistingRecommended = @(@(Get-PropertyValue -InputObject $ExistingReview -Name 'recommended') |
            Where-Object { $null -ne $_ })

    $ParsedExistingDate = [datetime]::MinValue

    if ([datetime]::TryParseExact(
            [string](Get-PropertyValue -InputObject $ExistingReview -Name 'reviewedOn'),
            'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$ParsedExistingDate))
    {
        $ExistingReviewDate = $ParsedExistingDate
    }
}

$RecommendationChanged = $null -eq $ExistingReview -or
    $null -eq $ExistingReviewDate -or
    ($ExistingCatalogRows -join "`n") -cne ($LiveCatalogRows -join "`n") -or
    ($ExistingRecommended -join "`n") -cne ($Recommended -join "`n")

# The stamp records when the result last changed, not when someone last ran this. Re-running on a
# later day against an identical catalog re-proves the same finding, so keep the date on record
# instead of rewriting three files to say exactly what they already said.
$EffectiveReviewDate = if ($RecommendationChanged) { $ReviewDate } else { $ExistingReviewDate }

$IsoDate = $EffectiveReviewDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$DisplayDate = $EffectiveReviewDate.ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
$OrdinalDate = Get-OrdinalDateText -Date $ReviewDate

$Review = [ordered]@{
    schemaVersion = 1
    reviewedOn = $IsoDate
    source = "One designated high-access VS Code profile's local model cache. This is a maintainer reference, not an entitlement guarantee for other users."
    catalogCount = $Records.Count
    catalog = @($Records | ForEach-Object {
            [ordered]@{
                name = $_.Name
                category = $_.Category
                isPreview = [bool]$_.IsPreview
            }
        })
    recommended = @($Recommended)
}

$NewLine = if ($InstallerText.Contains("`r`n")) { "`r`n" } else { "`n" }
$ReviewJson = ($Review | ConvertTo-Json -Depth 6) + $NewLine

$RecommendationDatePattern = '(?m)^\$RecommendationDate\s*=\s*''[^'']*''(?<Ending>\r?)$'

if ([regex]::Matches($InstallerText, $RecommendationDatePattern).Count -ne 1)
{
    throw 'The installer does not contain exactly one RecommendationDate assignment.'
}

$RecommendationDateLine = '$RecommendationDate = ''{0}''' -f $DisplayDate
$UpdatedInstaller = [regex]::Replace(
    $InstallerText,
    $RecommendationDatePattern,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param ($Match)
        return $RecommendationDateLine + $Match.Groups['Ending'].Value
    })

$LastModifiedPattern = '(?m)^(?<Label>    Last Modified:\r?\n)        [^\r\n]+(?<Ending>\r?)$'

if ([regex]::Matches($UpdatedInstaller, $LastModifiedPattern).Count -ne 1)
{
    throw 'The installer does not contain exactly one Last Modified entry.'
}

# Last Modified is release metadata, not a review stamp, so the gate never compares it and only a
# run that actually rewrites the recommendation moves it.
$InstallerToWrite = $UpdatedInstaller

if ($RecommendationChanged)
{
    $InstallerToWrite = [regex]::Replace(
        $UpdatedInstaller,
        $LastModifiedPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{
            param ($Match)
            return $Match.Groups['Label'].Value + '        ' + $OrdinalDate + $Match.Groups['Ending'].Value
        })
}

$ReadmeText = [System.IO.File]::ReadAllText($ReadmePath)
$ReadmeNewLine = if ($ReadmeText.Contains("`r`n")) { "`r`n" } else { "`n" }
$RecommendedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
foreach ($Name in $Recommended) { [void]$RecommendedSet.Add($Name) }

$BlockLines = New-Object System.Collections.Generic.List[string]
$BlockLines.Add('<!-- model-recommendation-review:start -->')
$BlockLines.Add("_Reference example reviewed **$DisplayDate** against one high-access VS Code profile._")
$BlockLines.Add('')
$BlockLines.Add('```text')

for ($Index = 0; $Index -lt $Records.Count; $Index++)
{
    if ($RecommendedSet.Contains($Records[$Index].Name))
    {
        $BlockLines.Add(('  * [{0}] {1}' -f ($Index + 1), $Records[$Index].Name))
    }
}

$BlockLines.Add('    [C] Enter a custom model name')
$BlockLines.Add('    [R] Use the recommended set marked with *')
$BlockLines.Add('```')
$BlockLines.Add('<!-- model-recommendation-review:end -->')
$RecommendationBlock = $BlockLines -join $ReadmeNewLine
$ReadmePattern = '(?s)<!-- model-recommendation-review:start -->.*?<!-- model-recommendation-review:end -->'

if ([regex]::Matches($ReadmeText, $ReadmePattern).Count -ne 1)
{
    throw 'README.md does not contain exactly one marked model recommendation block.'
}

$UpdatedReadme = [regex]::Replace(
    $ReadmeText,
    $ReadmePattern,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param ($Match)
        [void]$Match
        return $RecommendationBlock
    })

Write-Output ''
Write-Output "Live agent-capable catalog: $($Records.Count) models"
Write-Output "Recommendation reviewed on: $DisplayDate"
Write-Output 'Recommended set:'
foreach ($Name in $Recommended) { Write-Output "  $Name" }

if ($Update)
{
    $PendingChanges = New-Object System.Collections.Generic.List[string]

    if ($InstallerText -cne $InstallerToWrite) { $PendingChanges.Add('installer') }
    if ($ReadmeText -cne $UpdatedReadme) { $PendingChanges.Add('README example') }
    if ($null -eq $ExistingReviewJson -or $ExistingReviewJson -cne $ReviewJson) { $PendingChanges.Add('review snapshot') }

    if ($PendingChanges.Count -eq 0)
    {
        Write-Output ''
        Write-Output "Nothing to write. The live catalog still matches the review dated $DisplayDate."
        return
    }

    if ($PSCmdlet.ShouldProcess($RepositoryRoot, "Refresh the model recommendation review ($($PendingChanges -join ', '))"))
    {
        Set-Utf8FileContent -LiteralPath $InstallerPath -Content $InstallerToWrite
        Set-Utf8FileContent -LiteralPath $ReadmePath -Content $UpdatedReadme
        Set-Utf8FileContent -LiteralPath $ReviewPath -Content $ReviewJson
        Write-Output ''
        Write-Output "Updated: $($PendingChanges -join ', ')."
    }

    return
}

$Problems = New-Object System.Collections.Generic.List[string]

if ($null -ne $ExistingReviewProblem)
{
    $Problems.Add($ExistingReviewProblem)
}
else
{
    if ($null -eq $ExistingReviewDate)
    {
        $Problems.Add('the checked-in review has no usable yyyy-MM-dd reviewedOn date')
    }

    if (($ExistingCatalogRows -join "`n") -cne ($LiveCatalogRows -join "`n"))
    {
        $Problems.Add('the live profile catalog differs from the checked-in review')
    }

    if (($ExistingRecommended -join "`n") -cne ($Recommended -join "`n"))
    {
        $Problems.Add('the checked-in recommended set differs from the shipping algorithm result')
    }
}

if ($InstallerText -cne $UpdatedInstaller)
{
    $Problems.Add('the installer RecommendationDate does not match the checked-in review')
}

if ($ReadmeText -cne $UpdatedReadme)
{
    $Problems.Add('the README recommendation example does not match the checked-in review')
}

if ($Problems.Count -gt 0)
{
    $ProblemText = $Problems | ForEach-Object { "- $_" }
    throw "Model recommendation review failed:`n$($ProblemText -join "`n")`nRun .\.github\scripts\Update-ModelRecommendation.ps1 -Update from the designated high-access profile, inspect the diff, and commit it before pushing."
}

Write-Output ''
Write-Output 'Model recommendation review passed. The live cache and all tracked representations agree.'

$VerifiedOn = $ReviewDate.ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)

if ($EffectiveReviewDate -lt $ReviewDate)
{
    Write-Output "Re-verified against the live cache on $VerifiedOn. Unchanged since $DisplayDate, so no restamp is needed."
}