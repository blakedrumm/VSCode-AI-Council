<#
.SYNOPSIS
Creates release notes for a VS Code AI Council GitHub release.

.DESCRIPTION
Formats one or more additions as a change log, records the commit and the SHA-256 of both
published assets, and appends a download-count badge for the release version.

The .txt asset is a byte-identical copy of the .ps1, published for people whose mail gateway or
proxy refuses a .ps1 download. Publishing both digests lets a downloader prove they match.
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]
    $Version,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]
    $Repository,

    [Parameter()]
    [AllowEmptyString()]
    [string]
    $Additions = '',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $ScriptAssetName = 'Install-VSCodeCopilotCouncil-v5.ps1',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $TextAssetName = 'Install-VSCodeCopilotCouncil-v5.txt',

    [Parameter()]
    [AllowEmptyString()]
    [ValidatePattern('^(?:[0-9a-fA-F]{64})?$')]
    [string]
    $ScriptSha256 = '',

    [Parameter()]
    [AllowEmptyString()]
    [ValidatePattern('^(?:[0-9a-fA-F]{64})?$')]
    [string]
    $TextSha256 = '',

    [Parameter()]
    [AllowEmptyString()]
    [ValidatePattern('^(?:[0-9a-fA-F]{40})?$')]
    [string]
    $Commit = '',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$additionLines = [Collections.Generic.List[string]]::new()

foreach ($line in @($Additions -split '\r?\n'))
{
    # Additions are operator-supplied workflow input rendered into a public release body, so
    # control characters that could corrupt the markdown are dropped rather than escaped.
    $trimmedLine = ([regex]::Replace($line, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')).Trim()

    if ([string]::IsNullOrWhiteSpace($trimmedLine))
    {
        continue
    }

    $additionLines.Add('- ' + ($trimmedLine -replace '^[-*+]\s+', ''))
}

if ($additionLines.Count -eq 0)
{
    $additionLines.Add("- Released VS Code AI Council version $Version.")
}

$provenanceLines = [Collections.Generic.List[string]]::new()

if ($Commit)
{
    $provenanceLines.Add("- Built from commit ``$Commit``.")
}

if ($ScriptSha256)
{
    $provenanceLines.Add("- ``$ScriptAssetName`` SHA-256: ``$($ScriptSha256.ToLowerInvariant())``")
}

if ($TextSha256)
{
    $provenanceLines.Add("- ``$TextAssetName`` SHA-256: ``$($TextSha256.ToLowerInvariant())``")
}

if ($ScriptSha256 -and $TextSha256 -and $ScriptSha256 -eq $TextSha256)
{
    $provenanceLines.Add("- The .txt asset is byte-identical to the .ps1, for downloads that a .ps1 filter would block.")
}

$tagName = "v$Version"
$assetSegment = [Uri]::EscapeDataString($ScriptAssetName)
$badgeUrl = "https://img.shields.io/github/downloads/$Repository/$tagName/$assetSegment`?style=for-the-badge&color=brightgreen"
$downloadUrl = "https://github.com/$Repository/releases/download/$tagName/$assetSegment"

$content = @(
    '# Change Log'
    ''
    '## Additions'
    $additionLines.ToArray()
    if ($provenanceLines.Count -gt 0)
    {
        ''
        '## Package provenance'
        $provenanceLines.ToArray()
    }
    ''
    '## Install'
    ''
    'Download it, read it, then run it.'
    ''
    '```powershell'
    "Invoke-WebRequest -Uri '$downloadUrl' -OutFile '$ScriptAssetName'"
    "Unblock-File .\$ScriptAssetName"
    ".\$ScriptAssetName"
    '```'
    ''
    "[![Download Count $tagName]($badgeUrl)]($downloadUrl)"
) -join [Environment]::NewLine

$parentPath = Split-Path -Path $OutputPath -Parent

if ($parentPath -and -not (Test-Path -LiteralPath $parentPath))
{
    $null = New-Item -Path $parentPath -ItemType Directory -Force
}

[IO.File]::WriteAllText($OutputPath, $content + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $OutputPath
