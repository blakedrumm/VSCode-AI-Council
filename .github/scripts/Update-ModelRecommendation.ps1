#Requires -Version 5.1
<#
.SYNOPSIS
    Refreshes or verifies the checked-in model recommendation review.

.DESCRIPTION
    Runs the installer's shipping recommendation algorithm against a live local VS Code cache
    or official GitHub model tables. It installs nothing and does not change VS Code settings.

    Without -Update, this is a read-only pre-push gate. It verifies the source catalog, reference,
    fallback recommendation, unattended defaults, installer date, and marked README example.
    An unchanged result keeps its existing date and bytes, including on a later day.

    With -Update, it refreshes the embedded fallback catalog and categories, unattended defaults,
    .github/model-recommendation-review.json, installer review date, and marked README example.
    LocalCache must be run from the designated high-access profile. GitHubDocs requires the pinned
    powershell-yaml 0.4.12 module and retains reviewed categories for known model families rather
    than claiming public documentation exposes live cache metadata or account entitlements.

.PARAMETER Path
    Repository root. Defaults to the repository containing this script.

.PARAMETER ReviewDate
    Date recorded when the recommendation changed. Defaults to today. An unchanged recommendation
    keeps the date already on record rather than being restamped.

.PARAMETER Update
    Write changed recommendation data into the tracked representations. Identical output is left
    alone. Without this switch nothing is written.

.PARAMETER AllowReferenceContraction
    With -Update, permits a smaller local cache or an unexplained loss of a public recommendation.
    Use only after confirming the loss. Documented public retirements need no override. The weekly
    workflow never supplies this switch.

.PARAMETER Source
    LocalCache reads this machine's VS Code cache. GitHubDocs reads the official public model
    tables at one GitHub docs commit and carries forward reviewed categories only for newer
    versions of an existing model family. Unfamiliar families require a local-cache review.
    When omitted, uses the source recorded in the reference, or LocalCache for older references.

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
    $AllowReferenceContraction,

    [Parameter()]
    [ValidateSet('LocalCache', 'GitHubDocs')]
    [string]
    $Source
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

function ConvertTo-PublicModelCatalog
{
    param
    (
        [object[]]$Releases,
        [object[]]$Clients,
        [object[]]$Retirements,
        [object[]]$KnownRecords,
        [datetime]$AsOf
    )

    $Tables = @{ Releases = $Releases; Clients = $Clients; Retirements = $Retirements }
    foreach ($TableName in $Tables.Keys)
    {
        $Rows = @($Tables[$TableName])
        if ($Rows.Count -eq 0) { throw "The public $TableName table is empty." }
        $Seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Row in $Rows)
        {
            $Name = Get-PropertyValue -InputObject $Row -Name 'name'
            if ($Name -isnot [string] -or -not (Test-ModelName -Name $Name) -or -not $Seen.Add($Name))
            {
                throw "The public $TableName table contains an invalid or duplicate model name."
            }
        }
    }

    $ClientMap = @{}
    foreach ($Row in $Clients)
    {
        $Supported = Get-PropertyValue -InputObject $Row -Name 'vscode'
        if ($Supported -isnot [bool]) { throw "Missing or invalid VS Code support for $($Row.name)." }
        $ClientMap[$Row.name] = $Supported
    }

    $Retired = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Row in $Retirements)
    {
        $Date = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
                [string](Get-PropertyValue -InputObject $Row -Name 'retirement_date'),
                'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None, [ref]$Date))
        {
            throw "Invalid retirement date for $($Row.name)."
        }
        if ($Date.Date -le $AsOf.Date) { [void]$Retired.Add($Row.name) }
    }

    $Known = @{}
    foreach ($Row in $KnownRecords)
    {
        $Name = [string](Get-PropertyValue -InputObject $Row -Name 'name')
        $Category = [string](Get-PropertyValue -InputObject $Row -Name 'category')
        if ((Test-ModelName -Name $Name) -and $Category -cin @('powerful', 'versatile', 'lightweight') -and
            $Name -notmatch '(?i)^auto$|internal[\s\-]*only' -and
            -not (Test-PreviewModelName -Name $Name) -and
            -not [bool](Get-PropertyValue -InputObject $Row -Name 'isPreview'))
        {
            $Known[$Name] = [PSCustomObject]@{
                Name = $Name
                Category = $Category
                Family = [regex]::Replace($Name, '\d+(?:\.\d+)*', '#')
                Version = Get-ModelVersion -Name $Name
            }
        }
    }
    if ($Known.Count -eq 0) { throw 'No reviewed model categories are available for a public refresh.' }

    $Records = @{}
    $Unclassified = New-Object System.Collections.Generic.List[string]
    foreach ($Row in $Releases)
    {
        $Name = $Row.name
        $Status = Get-PropertyValue -InputObject $Row -Name 'release_status'
        if ($Status -isnot [string] -or $Status -notin @('GA', 'Public preview', 'Preview'))
        {
            throw "Unknown public release status for $Name. Review the upstream schema."
        }
        if ($Status -ne 'GA' -or $Retired.Contains($Name) -or
            (Test-PreviewModelName -Name $Name) -or $Name -match '(?i)^auto$|internal[\s\-]*only') { continue }
        if ($ClientMap.ContainsKey($Name) -and -not $ClientMap[$Name]) { continue }

        $Category = $null
        if ($Known.ContainsKey($Name))
        {
            $Category = $Known[$Name].Category
        }
        elseif ($ClientMap.ContainsKey($Name) -and $ClientMap[$Name])
        {
            $Family = [regex]::Replace($Name, '\d+(?:\.\d+)*', '#')
            $Version = Get-ModelVersion -Name $Name
            $Predecessors = @($Known.Values | Where-Object { $_.Family -ieq $Family -and $_.Version -lt $Version } |
                    Sort-Object -Property Version -Descending)
            if ($Predecessors.Count -gt 0)
            {
                $Latest = @($Predecessors | Where-Object { $_.Version -eq $Predecessors[0].Version })
                $Categories = @($Latest.Category | Select-Object -Unique)
                if ($Categories.Count -ne 1) { throw "Ambiguous reviewed category for $Name." }
                $Category = $Categories[0]
            }
        }

        if ($null -eq $Category)
        {
            $Unclassified.Add($Name)
            continue
        }
        $Records[$Name] = [PSCustomObject]@{ Name = $Name; Category = $Category; IsPreview = $false }
    }

    if ($Records.Count -eq 0) { throw 'No reviewed, supported model families survived the public refresh.' }
    $Names = [string[]]@($Records.Keys)
    [System.Array]::Sort($Names, [System.StringComparer]::OrdinalIgnoreCase)
    $Seeds = @{}
    foreach ($Record in @($Known.Values) + @($Records.Values))
    {
        $Seeds[$Record.Name] = [PSCustomObject]@{ name = $Record.Name; category = $Record.Category; isPreview = $false }
    }
    $SeedNames = [string[]]@($Seeds.Keys)
    [System.Array]::Sort($SeedNames, [System.StringComparer]::OrdinalIgnoreCase)
    return [PSCustomObject]@{
        Records = @($Names | ForEach-Object { $Records[$_] })
        Retired = @($Retired)
        Unclassified = @($Unclassified)
        CategorySeeds = @($SeedNames | ForEach-Object { $Seeds[$_] })
    }
}

function Get-GitHubModelTable
{
    param ([string]$Commit, [string]$Table)

    if ($Commit -cnotmatch '^[0-9a-f]{40}$' -or
        $Table -notin @('model-release-status', 'model-supported-clients', 'model-deprecation-history'))
    {
        throw 'Invalid public model table request.'
    }
    $Uri = "https://raw.githubusercontent.com/github/docs/$Commit/data/tables/copilot/$Table.yml"
    $Response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 0
    if ($Response.RawContentLength -gt 1048576) { throw "Public model table is unexpectedly large: $Table." }
    $Rows = ConvertFrom-Yaml -Yaml $Response.Content
    if ($Rows -isnot [System.Collections.IList]) { throw "Expected a YAML sequence in $Table." }
    foreach ($Row in $Rows)
    {
        if ($Row -isnot [System.Collections.IDictionary]) { throw "Invalid YAML row in $Table." }
        [PSCustomObject]$Row
    }
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

foreach ($VariableName in @('LensCatalog', 'DefaultModelCatalog', 'DefaultModelCategoryMap', 'DefaultModels'))
{
    $Assignment = Get-AssignmentStatement -Ast $InstallerAst -VariableName $VariableName
    . ([scriptblock]::Create($Assignment.Extent.Text))
}

$MaximumCount = $LensCatalog.Count

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

if ([string]::IsNullOrEmpty($Source))
{
    $Source = if ($null -ne $ExistingReview) { [string](Get-PropertyValue -InputObject $ExistingReview -Name 'sourceKind') } else { '' }
    if ([string]::IsNullOrEmpty($Source)) { $Source = 'LocalCache' }
    if ($Source -notin @('LocalCache', 'GitHubDocs')) { throw 'Unrecognized reference sourceKind.' }
}

$PublicCatalog = $null
$SourceCommit = $null
if ($Source -eq 'GitHubDocs')
{
    Import-Module powershell-yaml -RequiredVersion 0.4.12 -ErrorAction Stop
    $CommitRecord = Invoke-RestMethod -Uri 'https://api.github.com/repos/github/docs/commits/main' -TimeoutSec 60 -MaximumRedirection 0
    $SourceCommit = [string](Get-PropertyValue -InputObject $CommitRecord -Name 'sha')
    $KnownRecords = @($DefaultModelCatalog | ForEach-Object {
            [PSCustomObject]@{ name = $_; category = $DefaultModelCategoryMap[$_]; isPreview = $false }
        })
    if ($null -ne $ExistingReview)
    {
        $KnownRecords += @(@(Get-PropertyValue -InputObject $ExistingReview -Name 'categorySeeds') | Where-Object { $null -ne $_ })
        $KnownRecords += @(Get-PropertyValue -InputObject $ExistingReview -Name 'catalog')
    }
    $PublicCatalog = ConvertTo-PublicModelCatalog `
        -Releases @(Get-GitHubModelTable -Commit $SourceCommit -Table 'model-release-status') `
        -Clients @(Get-GitHubModelTable -Commit $SourceCommit -Table 'model-supported-clients') `
        -Retirements @(Get-GitHubModelTable -Commit $SourceCommit -Table 'model-deprecation-history') `
        -KnownRecords $KnownRecords -AsOf $ReviewDate
    $Records = @($PublicCatalog.Records)
    if ($PublicCatalog.Unclassified.Count -gt 0)
    {
        Write-Warning "Not automatically classified; review these models from a live cache: $($PublicCatalog.Unclassified -join ', ')."
    }
}
else
{
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
}

if ($Records.Count -eq 0)
{
    throw 'No model records were read. Nothing was updated or verified.'
}

if ($Update -and $null -ne $ExistingReview)
{
    $PreviousCatalog = @(Get-PropertyValue -InputObject $ExistingReview -Name 'catalog')
    $PreviousRecommended = @(Get-PropertyValue -InputObject $ExistingReview -Name 'recommended')
    $CurrentNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Record in $Records) { [void]$CurrentNames.Add($Record.Name) }

    $MissingPreviousRecommendations = @($PreviousRecommended | Where-Object { -not $CurrentNames.Contains($_) })
    $ReferenceContracted = $Records.Count -lt $PreviousCatalog.Count -or $MissingPreviousRecommendations.Count -gt 0

    if ($Source -eq 'GitHubDocs')
    {
        $UnexplainedLoss = @($MissingPreviousRecommendations | Where-Object { $PublicCatalog.Retired -notcontains $_ })
        $ReferenceContracted = $UnexplainedLoss.Count -gt 0
    }

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

        throw "The $Source catalog contracted from $($PreviousCatalog.Count) to $($Records.Count) records.$MissingText Refusing to replace the reference. Confirm this is a real catalog change, then re-run with -Update -AllowReferenceContraction."
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
    throw "The $Source catalog produced $($Recommended.Count) recommendation(s) for $MaximumCount seats. Review the source before updating the reference."
}

$CatalogInstallerText = $InstallerText
if ($Update)
{
    $DefaultModelCatalog = @($Records | Where-Object { $_.Name -notmatch '(?i)^auto$|internal[\s\-]*only' } | ForEach-Object { $_.Name })
    $DefaultModelCategoryMap = @{}
    foreach ($Record in $Records)
    {
        if ($DefaultModelCatalog -contains $Record.Name) { $DefaultModelCategoryMap[$Record.Name] = $Record.Category }
    }
    $DefaultModels = @($Recommended | Select-Object -First 2)
    $LineEnding = if ($InstallerText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $CatalogLines = @($DefaultModelCatalog | ForEach-Object { "    '$($_.Replace("'", "''"))'" })
    $CategoryLines = @($DefaultModelCatalog | ForEach-Object {
            "    '$($_.Replace("'", "''"))' = '$(([string]$DefaultModelCategoryMap[$_]).Replace("'", "''"))'"
        })
    $DefaultLiterals = @($DefaultModels | ForEach-Object { "'$($_.Replace("'", "''"))'" })
    $Replacements = @{
        DefaultModelCatalog = '$DefaultModelCatalog = @(' + $LineEnding + ($CatalogLines -join (',' + $LineEnding)) + $LineEnding + ')'
        DefaultModelCategoryMap = '$DefaultModelCategoryMap = @{' + $LineEnding + ($CategoryLines -join $LineEnding) + $LineEnding + '}'
        DefaultModels = '$DefaultModels = @(' + ($DefaultLiterals -join ', ') + ')'
    }
    $Assignments = @($Replacements.Keys | ForEach-Object { Get-AssignmentStatement -Ast $InstallerAst -VariableName $_ } |
            Sort-Object { $_.Extent.StartOffset } -Descending)
    foreach ($Assignment in $Assignments)
    {
        $Replacement = $Replacements[$Assignment.Left.VariablePath.UserPath]
        $CatalogInstallerText = $CatalogInstallerText.Remove($Assignment.Extent.StartOffset, $Assignment.Extent.EndOffset - $Assignment.Extent.StartOffset).
            Insert($Assignment.Extent.StartOffset, $Replacement)
    }
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

$ExpectedDefaults = @($Recommended | Select-Object -First 2)
if (($DefaultModels -join "`n") -cne ($ExpectedDefaults -join "`n"))
{
    throw 'The unattended DefaultModels pair differs from the reviewed recommendation. Run with -Update before continuing.'
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
    [string](Get-PropertyValue -InputObject $ExistingReview -Name 'sourceKind') -cne $Source -or
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

$Review.sourceKind = $Source
if ($Source -eq 'GitHubDocs')
{
    $Review.source = 'Official GitHub docs model tables, filtered to reviewed model families. Categories and existing VS Code support are inherited from the last reviewed cache; new versions require explicit public VS Code support. Not a live cache or entitlement check.'
    $Review.sourceCommit = if ($RecommendationChanged) { $SourceCommit } else { Get-PropertyValue -InputObject $ExistingReview -Name 'sourceCommit' }
    $Review.sourceUrl = 'https://docs.github.com/en/copilot/reference/ai-models/supported-models'
    $Review.categorySeeds = @($PublicCatalog.CategorySeeds)
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
    $CatalogInstallerText,
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
$ReferenceDescription = if ($Source -eq 'GitHubDocs') { 'official GitHub model tables and previously reviewed family metadata' } else { 'one high-access VS Code profile' }
$BlockLines.Add("_Reference example reviewed **$DisplayDate** against $ReferenceDescription._")
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
Write-Output "$Source model catalog: $($Records.Count) models"
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
        Write-Output "Nothing to write. The $Source catalog still matches the review dated $DisplayDate."
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
    throw "Model recommendation review failed:`n$($ProblemText -join "`n")`nRun .\.github\scripts\Update-ModelRecommendation.ps1 -Source $Source -Update, inspect the diff, and commit it before pushing. LocalCache requires the designated high-access profile."
}

Write-Output ''
Write-Output "Model recommendation review passed. The $Source catalog and all tracked representations agree."

$VerifiedOn = $ReviewDate.ToString('MMMM d, yyyy', [System.Globalization.CultureInfo]::InvariantCulture)

if ($EffectiveReviewDate -lt $ReviewDate)
{
    Write-Output "Re-verified against $Source on $VerifiedOn. Unchanged since $DisplayDate, so no restamp is needed."
}