BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepositoryRoot = Split-Path $PSScriptRoot -Parent
    foreach ($File in @('Install-VSCodeCopilotCouncil-v5.ps1', '.github/scripts/Update-ModelRecommendation.ps1'))
    {
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepositoryRoot $File), [ref]$Tokens, [ref]$Errors)
        if ($Errors.Count -gt 0) { throw ($Errors.Message -join '; ') }
        foreach ($Definition in $Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        {
            if ($Definition.Name -in @('Get-PropertyValue', 'Test-ModelName', 'Test-PreviewModelName', 'Get-ModelVersion', 'ConvertTo-PublicModelCatalog', 'Get-GitHubModelTable'))
            {
                . ([scriptblock]::Create($Definition.Extent.Text))
            }
        }
    }

    function ConvertFrom-Yaml {
        param ([string]$Yaml)
        throw "Unexpected unmocked YAML conversion: $Yaml"
    }

    function New-RecommendationFixture {
        param ([object[]]$Records)

        $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -Path (Join-Path $Root '.github') -ItemType Directory -Force
        $Text = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot 'Install-VSCodeCopilotCouncil-v5.ps1'))
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
        $Reader = $Ast.Find({ param ($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-VSCodeModelCatalog' }, $true)
        $Json = ConvertTo-Json -InputObject @($Records) -Depth 6 -Compress
        $Replacement = "function Get-VSCodeModelCatalog { `$Rows = '$($Json.Replace("'", "''"))' | ConvertFrom-Json; foreach (`$Row in `$Rows) { `$Row } }"
        $Text = $Text.Remove($Reader.Extent.StartOffset, $Reader.Extent.EndOffset - $Reader.Extent.StartOffset).Insert($Reader.Extent.StartOffset, $Replacement)
        [System.IO.File]::WriteAllText((Join-Path $Root 'Install-VSCodeCopilotCouncil-v5.ps1'), $Text, (New-Object System.Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'README.md') -Destination $Root
        Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot '.github/model-recommendation-review.json') -Destination (Join-Path $Root '.github')
        return $Root
    }

    function Get-RecommendationFixtureHash {
        param ([string]$Root)

        foreach ($Name in @('Install-VSCodeCopilotCouncil-v5.ps1', 'README.md', '.github/model-recommendation-review.json'))
        {
            (Get-FileHash -LiteralPath (Join-Path $Root $Name) -Algorithm SHA256).Hash
        }
    }
}

Describe 'Public model table loader' {
    BeforeEach {
        Mock Invoke-WebRequest { [PSCustomObject]@{ Content = 'fixture'; RawContentLength = 7 } }
        Mock ConvertFrom-Yaml {
            $Rows = New-Object System.Collections.Generic.List[object]
            $Rows.Add(@{ name = 'Claude Opus 5.5'; release_status = 'GA' })
            $Rows.Add(@{ name = 'GPT-6.1 Sol'; release_status = 'GA' })
            Write-Output -InputObject $Rows -NoEnumerate
        }
    }

    It 'enumerates the sequence returned as one pipeline object by the YAML parser' {
        $Rows = @(Get-GitHubModelTable -Commit ('a' * 40) -Table 'model-release-status')
        $Rows.Count | Should -Be 2
        @($Rows.name) | Should -Be @('Claude Opus 5.5', 'GPT-6.1 Sol')
    }

    It 'rejects a mapping in place of a sequence' {
        Mock ConvertFrom-Yaml { @{ name = 'Claude Opus 5.5'; release_status = 'GA' } }
        { Get-GitHubModelTable -Commit ('a' * 40) -Table 'model-release-status' } | Should -Throw '*YAML sequence*'
    }

    It 'rejects unpinned commits and unknown table paths before fetching' {
        { Get-GitHubModelTable -Commit 'main' -Table 'model-release-status' } | Should -Throw '*Invalid public model table request*'
        { Get-GitHubModelTable -Commit ('a' * 40) -Table '../other' } | Should -Throw '*Invalid public model table request*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
}

Describe 'Public model recommendation source' {
    BeforeEach {
        $script:InputRecords = @{
            Releases = @(
                [PSCustomObject]@{ name = 'Claude Opus 5.5'; release_status = 'GA' }
                [PSCustomObject]@{ name = 'GPT-6.1 Sol'; release_status = 'GA' }
                [PSCustomObject]@{ name = 'GPT-6.1 Luna'; release_status = 'GA' }
                [PSCustomObject]@{ name = 'NewVendor 8'; release_status = 'GA' }
            )
            Clients = @(
                [PSCustomObject]@{ name = 'Claude Opus 5.5'; vscode = $true }
                [PSCustomObject]@{ name = 'GPT-6.1 Sol'; vscode = $true }
                [PSCustomObject]@{ name = 'GPT-6.1 Luna'; vscode = $true }
                [PSCustomObject]@{ name = 'NewVendor 8'; vscode = $true }
            )
            Retirements = @([PSCustomObject]@{ name = 'Claude Opus 4'; retirement_date = '2025-10-23' })
            KnownRecords = @(
                [PSCustomObject]@{ name = 'Claude Opus 5'; category = 'powerful'; isPreview = $false }
                [PSCustomObject]@{ name = 'GPT-6 Sol'; category = 'powerful'; isPreview = $false }
                [PSCustomObject]@{ name = 'GPT-6 Luna'; category = 'lightweight'; isPreview = $false }
            )
            AsOf = [datetime]'2026-10-01'
        }
    }

    It 'refreshes reviewed families while retaining their exact category and ordinal order' {
        $Actual = ConvertTo-PublicModelCatalog @script:InputRecords
        @($Actual.Records.Name) | Should -Be @('Claude Opus 5.5', 'GPT-6.1 Luna', 'GPT-6.1 Sol')
        @($Actual.Records.Category) | Should -Be @('powerful', 'lightweight', 'powerful')
        @($Actual.Unclassified) | Should -Be @('NewVendor 8')
    }

    It 'does not infer a new family or trust a name as a size hint' {
        $script:InputRecords.KnownRecords = @([PSCustomObject]@{ name = 'Claude Opus 5'; category = 'versatile'; isPreview = $false })
        $Actual = ConvertTo-PublicModelCatalog @script:InputRecords
        @($Actual.Records.Category) | Should -Be @('versatile')
        @($Actual.Unclassified) | Should -Contain 'GPT-6.1 Sol'
    }

    It 'requires explicit VS Code support for newly inferred versions' {
        $script:InputRecords.Clients = @($script:InputRecords.Clients | Where-Object { $_.name -ne 'GPT-6.1 Sol' })
        $Actual = ConvertTo-PublicModelCatalog @script:InputRecords
        @($Actual.Records.Name) | Should -Not -Contain 'GPT-6.1 Sol'
    }

    It 'preserves reviewed support when a known model is missing from the client table' {
        $script:InputRecords.KnownRecords += [PSCustomObject]@{ name = 'GPT-6.1 Sol'; category = 'powerful'; isPreview = $false }
        $script:InputRecords.Clients = @($script:InputRecords.Clients | Where-Object { $_.name -ne 'GPT-6.1 Sol' })
        @((ConvertTo-PublicModelCatalog @script:InputRecords).Records.Name) | Should -Contain 'GPT-6.1 Sol'
    }

    It 'honors an explicit withdrawal of VS Code support even for a known model' {
        $script:InputRecords.KnownRecords += [PSCustomObject]@{ name = 'GPT-6.1 Sol'; category = 'powerful'; isPreview = $false }
        $script:InputRecords.Clients[1].vscode = $false
        @((ConvertTo-PublicModelCatalog @script:InputRecords).Records.Name) | Should -Not -Contain 'GPT-6.1 Sol'
    }

    It 'excludes retired models on their retirement day' {
        $script:InputRecords.Retirements += [PSCustomObject]@{ name = 'Claude Opus 5.5'; retirement_date = '2026-10-01' }
        $Actual = ConvertTo-PublicModelCatalog @script:InputRecords
        @($Actual.Records.Name) | Should -Not -Contain 'Claude Opus 5.5'
        @($Actual.Retired) | Should -Contain 'Claude Opus 5.5'
    }

    It 'does not remove a model before its retirement date' {
        $script:InputRecords.Retirements += [PSCustomObject]@{ name = 'Claude Opus 5.5'; retirement_date = '2026-10-02' }
        @((ConvertTo-PublicModelCatalog @script:InputRecords).Records.Name) | Should -Contain 'Claude Opus 5.5'
    }

    It 'retains category history when a successor arrives after the last family member retires' {
        $script:InputRecords.KnownRecords += [PSCustomObject]@{ name = 'Grok 4.7'; category = 'versatile'; isPreview = $false }
        $script:InputRecords.Releases += [PSCustomObject]@{ name = 'Grok 4.7'; release_status = 'GA' }
        $script:InputRecords.Clients += [PSCustomObject]@{ name = 'Grok 4.7'; vscode = $true }
        $script:InputRecords.Retirements += [PSCustomObject]@{ name = 'Grok 4.7'; retirement_date = '2026-10-01' }
        $First = ConvertTo-PublicModelCatalog @script:InputRecords
        @($First.Records.Name) | Should -Not -Contain 'Grok 4.7'
        $script:InputRecords.KnownRecords = @($First.CategorySeeds) + @($First.Records)
        $script:InputRecords.Releases += [PSCustomObject]@{ name = 'Grok 4.8'; release_status = 'GA' }
        $script:InputRecords.Clients += [PSCustomObject]@{ name = 'Grok 4.8'; vscode = $true }
        $Second = ConvertTo-PublicModelCatalog @script:InputRecords
        @($Second.Records.Name) | Should -Contain 'Grok 4.8'
        ($Second.Records | Where-Object { $_.Name -eq 'Grok 4.8' }).Category | Should -Be 'versatile'
    }

    It 'does not automatically promote preview releases' {
        $script:InputRecords.Releases[0].release_status = 'Public preview'
        @((ConvertTo-PublicModelCatalog @script:InputRecords).Records.Name) | Should -Not -Contain 'Claude Opus 5.5'
    }

    It 'rejects malformed or duplicate upstream names' {
        $script:InputRecords.Releases += $script:InputRecords.Releases[0]
        { ConvertTo-PublicModelCatalog @script:InputRecords } | Should -Throw '*invalid or duplicate*'
    }

    It 'fails closed on an unknown release status' {
        $script:InputRecords.Releases[0].release_status = 'unknown'
        { ConvertTo-PublicModelCatalog @script:InputRecords } | Should -Throw '*release status*'
    }

    It 'does not coerce a string false into true' {
        $script:InputRecords.Clients[0].vscode = 'false'
        { ConvertTo-PublicModelCatalog @script:InputRecords } | Should -Throw '*VS Code support*'
    }

    It 'fails closed on an empty required table' {
        $script:InputRecords.Clients = @()
        { ConvertTo-PublicModelCatalog @script:InputRecords } | Should -Throw '*table is empty*'
    }

    It 'fails closed on an invalid retirement date' {
        $script:InputRecords.Retirements[0].retirement_date = 'not-a-date'
        { ConvertTo-PublicModelCatalog @script:InputRecords } | Should -Throw '*retirement date*'
    }
}

Describe 'Recommendation updater file contract' {
    BeforeEach {
        $script:UpdaterPath = Join-Path $script:RepositoryRoot '.github/scripts/Update-ModelRecommendation.ps1'
        $script:Reference = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github/model-recommendation-review.json')) | ConvertFrom-Json
        $script:FixtureRecords = @($script:Reference.catalog)
    }

    It 'refreshes fallback data, unattended defaults, reference, and README before passing the read-only gate' {
        $script:FixtureRecords += [PSCustomObject]@{ name = 'Claude Opus 99.1'; category = 'powerful'; isPreview = $false }
        $Root = New-RecommendationFixture -Records $script:FixtureRecords
        & $script:UpdaterPath -Path $Root -Source LocalCache -ReviewDate '2030-01-02' -Update | Out-Null
        $Review = [System.IO.File]::ReadAllText((Join-Path $Root '.github/model-recommendation-review.json')) | ConvertFrom-Json
        @($Review.recommended) | Should -Contain 'Claude Opus 99.1'
        $Review.sourceKind | Should -Be 'LocalCache'
        $Review.reviewedOn | Should -Be '2030-01-02'
        $Installer = [System.IO.File]::ReadAllText((Join-Path $Root 'Install-VSCodeCopilotCouncil-v5.ps1'))
        $Installer | Should -Match "'Claude Opus 99\.1' = 'powerful'"
        $Installer | Should -Match '\$DefaultModels = @\(''Claude Opus 99\.1'', '
        { & $script:UpdaterPath -Path $Root -Source LocalCache -ReviewDate '2030-01-02' | Out-Null } | Should -Not -Throw
    }

    It 'keeps unchanged recommendations byte-identical even when checked on a later day' {
        $Root = New-RecommendationFixture -Records $script:FixtureRecords
        & $script:UpdaterPath -Path $Root -Source LocalCache -ReviewDate '2030-01-02' -Update | Out-Null
        $Before = @(Get-RecommendationFixtureHash -Root $Root)
        & $script:UpdaterPath -Path $Root -ReviewDate '2030-01-03' -Update | Out-Null
        @(Get-RecommendationFixtureHash -Root $Root) | Should -Be $Before
    }

    It 'does not write any tracked representation during WhatIf' {
        $script:FixtureRecords += [PSCustomObject]@{ name = 'Claude Opus 99.1'; category = 'powerful'; isPreview = $false }
        $Root = New-RecommendationFixture -Records $script:FixtureRecords
        $Before = @(Get-RecommendationFixtureHash -Root $Root)
        & $script:UpdaterPath -Path $Root -Source LocalCache -ReviewDate '2030-01-02' -Update -WhatIf | Out-Null
        @(Get-RecommendationFixtureHash -Root $Root) | Should -Be $Before
    }

    It 'refuses a contracted local reference without writing any files' {
        $Missing = $script:Reference.recommended[0]
        $Root = New-RecommendationFixture -Records @($script:FixtureRecords | Where-Object { $_.name -ne $Missing })
        $Before = @(Get-RecommendationFixtureHash -Root $Root)
        { & $script:UpdaterPath -Path $Root -Source LocalCache -Update | Out-Null } | Should -Throw '*catalog contracted*'
        @(Get-RecommendationFixtureHash -Root $Root) | Should -Be $Before
    }

    It 'reports recommendation drift without mutating a read-only run' {
        $script:FixtureRecords += [PSCustomObject]@{ name = 'Claude Opus 99.1'; category = 'powerful'; isPreview = $false }
        $Root = New-RecommendationFixture -Records $script:FixtureRecords
        $Before = @(Get-RecommendationFixtureHash -Root $Root)
        { & $script:UpdaterPath -Path $Root -Source LocalCache | Out-Null } | Should -Throw
        @(Get-RecommendationFixtureHash -Root $Root) | Should -Be $Before
    }

    It 'rejects an unattended default pair that no longer matches the recommendation' {
        $Root = New-RecommendationFixture -Records $script:FixtureRecords
        & $script:UpdaterPath -Path $Root -Source LocalCache -Update | Out-Null
        $Path = Join-Path $Root 'Install-VSCodeCopilotCouncil-v5.ps1'
        $Text = [System.IO.File]::ReadAllText($Path)
        $Text = [regex]::Replace($Text, '(?m)^\$DefaultModels = [^\r\n]+', [System.Text.RegularExpressions.MatchEvaluator]{ '$DefaultModels = @(''Auto'')' })
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
        { & $script:UpdaterPath -Path $Root -Source LocalCache | Out-Null } | Should -Throw '*DefaultModels pair*'
    }
}