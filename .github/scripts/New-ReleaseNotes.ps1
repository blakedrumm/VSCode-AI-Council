<#
.SYNOPSIS
Creates release notes for a VS Code AI Council GitHub release.

.DESCRIPTION
Formats the release body, records the commit and the SHA-256 of both published assets, and appends
a download-count badge for the release version.

The body text comes from the CHANGELOG section matching the version, so the release notes and the
repository history cannot drift apart. Explicit additions override that for an ad-hoc release.

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

    [Parameter()]
    [AllowEmptyString()]
    [string]
    $ChangelogPath = 'CHANGELOG.md',

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

$changelogLines = [Collections.Generic.List[string]]::new()

if ($additionLines.Count -eq 0 -and $ChangelogPath -and (Test-Path -LiteralPath $ChangelogPath))
{
    $collecting = $false

    foreach ($line in @([IO.File]::ReadAllText($ChangelogPath) -split '\r?\n'))
    {
        if ($line -match '^##(?!#)\s+')
        {
            if ($collecting)
            {
                break
            }

            $heading = ($line -replace '^##\s+', '').Trim()

            if ($heading -match "^\[?v?$([regex]::Escape($Version))\]?(?:\s|$)")
            {
                $collecting = $true
            }

            continue
        }

        if ($collecting)
        {
            $sanitizedLine = [regex]::Replace($line, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '')

            # Promoted so the section renders one level under the release body's own title.
            $promotedLine = $sanitizedLine -replace '^###\s+', '## '

            $changelogLines.Add($promotedLine)
        }
    }

    while ($changelogLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($changelogLines[0]))
    {
        $changelogLines.RemoveAt(0)
    }

    while ($changelogLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($changelogLines[$changelogLines.Count - 1]))
    {
        $changelogLines.RemoveAt($changelogLines.Count - 1)
    }
}

if ($additionLines.Count -eq 0 -and $changelogLines.Count -eq 0)
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
    "# VS Code AI Council $Version"
    ''
    if ($changelogLines.Count -gt 0)
    {
        $changelogLines.ToArray()
    }
    else
    {
        '## Additions'
        $additionLines.ToArray()
    }
    if ($provenanceLines.Count -gt 0)
    {
        ''
        '## Package provenance'
        ''
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
