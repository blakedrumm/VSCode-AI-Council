BeforeAll {
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:InstallerPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'Install-VSCodeCopilotCouncil-v5.ps1'
    $Tokens = $null
    $ParseErrors = $null
    $script:InstallerAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:InstallerPath,
        [ref]$Tokens,
        [ref]$ParseErrors)

    if ($ParseErrors.Count -gt 0)
    {
        throw ($ParseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } | Out-String)
    }

    $FunctionNames = @(
        'Write-Console',
        'ConvertTo-NormalizedText',
        'Write-Utf8File',
        'Read-Utf8File',
        'Get-FileStateSnapshot',
        'Test-RestoreIsSafe',
        'Restore-FileStateSnapshot',
        'Backup-ExistingFile',
        'Remove-ExpiredBackup',
        'Test-ModelName',
        'ConvertTo-AgentSlug',
        'Get-PropertyValue',
        'Initialize-SqliteInterop',
        'ConvertFrom-ModelCacheJson',
        'Get-CachedModelRecord',
        'Get-VSCodeModelCatalog',
        'Get-PreviousCouncilConfiguration',
        'Get-ModelFamily',
        'Get-ModelTierWeight',
        'Get-ModelVersion',
        'Get-RecommendedModelSet',
        'Select-ModelList',
        'ConvertTo-CommentMaskedJson',
        'ConvertFrom-JsoncText',
        'Get-RootJsonPropertyToken',
        'Set-VSCodeNestedSubagentsSetting',
        'New-AgentFrontMatter',
        'New-ReviewerAgentContent',
        'New-ExpertAgentContent',
        'New-CoordinatorAgentContent',
        'Test-OwnedAgentFile',
        'Test-AgentFile',
        'Test-GeneratedAgentFile',
        'Get-PublishedScriptVersion',
        'Select-CoordinatorModel',
        'Get-VSCodeUserSettingsPath',
        'Get-VSCodeStatus'
    )

    foreach ($FunctionName in $FunctionNames)
    {
        $FunctionAst = $script:InstallerAst.Find(
            {
                param ($Node)

                return $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $Node.Name -eq $FunctionName
            },
            $true)

        if ($null -eq $FunctionAst)
        {
            throw "Could not find function in installer AST: $FunctionName"
        }

        . ([scriptblock]::Create($FunctionAst.Extent.Text))
    }

    # The generators read these script-level constants, so the harness has to load the real values
    # rather than restate them, or the tests would stop tracking the installer.
    foreach ($ConstantName in @('ReviewerAgentTools', 'ExpertAgentTools', 'CoordinatorAgentTools', 'EvidenceHierarchy', 'EvidenceHierarchyText', 'LensCatalog', 'MaxModelCount', 'BackupRetentionCount'))
    {
        $ConstantAst = $script:InstallerAst.Find(
            {
                param ($Node)

                return $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.Left.VariablePath.UserPath -eq $ConstantName
            },
            $true)

        if ($null -eq $ConstantAst)
        {
            throw "Could not find constant in installer AST: $ConstantName"
        }

        . ([scriptblock]::Create($ConstantAst.Extent.Text))
        Set-Variable -Name $ConstantName -Scope 'Script' -Value (Get-Variable -Name $ConstantName -ValueOnly)
    }
}

Describe 'PowerShell syntax' {
    It 'parses without errors' {
        $script:InstallerAst | Should -Not -BeNullOrEmpty
    }

    # PowerShell cannot infer the generic argument, so this silently fails on both editions rather
    # than erroring at parse time. It reached the release-notes generator once already.
    It 'does not call a generic LINQ method PowerShell cannot bind' {
        $InstallerText = [System.IO.File]::ReadAllText($script:InstallerPath)

        $InstallerText | Should -Not -Match 'System\.Linq\.Enumerable'
    }

    # PowerShell attributes take constants, so the -Models limit cannot reference $MaxModelCount.
    # Adding a sixth lens would otherwise leave users unable to supply enough models to fill it.
    It 'caps -Models at exactly the number of available lenses' {
        $ParamBlock = $script:InstallerAst.ParamBlock
        $ModelsParameter = $ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'Models' }

        $ValidateCount = $ModelsParameter.Attributes |
            Where-Object { $_.TypeName.Name -eq 'ValidateCount' }

        [int]$ValidateCount.PositionalArguments[1].Value | Should -Be $script:LensCatalog.Count
    }
}

Describe 'Model input and recommendation' {
    It 'accepts a normal model name' {
        Test-ModelName -Name 'Claude Opus 5' | Should -BeTrue
    }

    It 'rejects unsafe or unbounded model names' -TestCases @(
        @{ Candidate = '' }
        @{ Candidate = ' Model' }
        @{ Candidate = 'Model ' }
        @{ Candidate = ('A' * 101) }
        @{ Candidate = 'Model: injected' }
        @{ Candidate = "Model$([char]0x200F)Name" }
        @{ Candidate = "Model$([char]0x2028)Name" }
        @{ Candidate = "Model$([char]0x2029)Name" }
        @{ Candidate = "Model$([char]0x007F)Name" }
        @{ Candidate = "Model$([char]0x0080)Name" }
        @{ Candidate = "Model$([char]0x009F)Name" }
        @{ Candidate = "Model$([char]0xFFFE)Name" }
        @{ Candidate = "Model$([char]0xFFFF)Name" }
    ) {
        param ($Candidate)

        Test-ModelName -Name $Candidate | Should -BeFalse
    }

    It 'fails closed when a version number overflows Int32' {
        (Get-ModelVersion -Name 'Model 999999999999999999999').ToString() | Should -Be '0.0'
    }

    It 'deduplicates recommendations case-insensitively' {
        $Recommended = @(Get-RecommendedModelSet `
                -Catalog @('Claude Opus 5', 'claude opus 5', 'Grok 4.5') `
                -MaximumCount 5 `
                -CategoryMap @{})

        $Recommended.Count | Should -Be 2
    }

    It 'treats uppercase C as the custom-model command' {
        $script:PickerResponses = [System.Collections.Generic.Queue[string]]::new()
        @('C', 'Custom Model', 'Y') | ForEach-Object { $script:PickerResponses.Enqueue($_) }
        Mock Read-Host { return $script:PickerResponses.Dequeue() }

        $Selected = @(Select-ModelList `
                -Catalog @('Claude Opus 5') `
                -MaximumCount 5 `
                -Discovered $false `
                -Recommended @() `
                -LensTitles @('Implementation and correctness') `
                -RecommendationDate 'test')

        $Selected | Should -Be @('Custom Model')
    }
}

Describe 'VS Code model-cache resilience' {
    It 'flattens a top-level model array on every PowerShell edition' {
        $Records = @(ConvertFrom-ModelCacheJson -Json '[{"identifier":"one"},{"identifier":"two"}]')

        $Records.Count | Should -Be 2
        $Records[0].identifier | Should -Be 'one'
        $Records[1].identifier | Should -Be 'two'
    }

    It 'does not trust an older same-namespace SQLite wrapper' {
        if ($null -eq ('VSCodeCouncil.Sqlite' -as [type]))
        {
            Add-Type -Namespace 'VSCodeCouncil' -Name 'Sqlite' -MemberDefinition 'public static int LegacyMarker() { return 1; }'
        }

        Initialize-SqliteInterop | Should -BeTrue
        ('VSCodeCouncil.SqliteCacheV1' -as [type]) | Should -Not -BeNullOrEmpty
    }

    It 'retries one fresh snapshot before returning an empty catalog' {
        $OriginalAppData = $env:APPDATA
        $CacheRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-cache-$([guid]::NewGuid().ToString('N'))"

        try
        {
            $env:APPDATA = $CacheRoot
            $StateDirectory = Join-Path $CacheRoot 'Code\User\globalStorage'
            New-Item -Path $StateDirectory -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $StateDirectory 'state.vscdb') -ItemType File -Force | Out-Null
            $script:CacheAttempts = 0

            Mock Initialize-SqliteInterop { return $true }
            Mock Get-CachedModelRecord {
                $script:CacheAttempts++

                if ($script:CacheAttempts -eq 1)
                {
                    return [PSCustomObject]@{ Succeeded = $false; Records = @() }
                }

                return [PSCustomObject]@{
                    Succeeded = $true
                    Records = @([PSCustomObject]@{ Name = 'Recovered Model'; Category = 'powerful' })
                }
            }

            $Models = @(Get-VSCodeModelCatalog)

            $script:CacheAttempts | Should -Be 2
            $Models.Count | Should -Be 1
            $Models[0].Name | Should -Be 'Recovered Model'
        }
        finally
        {
            $env:APPDATA = $OriginalAppData
            Remove-Variable CacheAttempts -Scope Script -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not retry a snapshot that read cleanly with no agent-capable model' {
        $OriginalAppData = $env:APPDATA
        $CacheRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-cache-$([guid]::NewGuid().ToString('N'))"

        try
        {
            $env:APPDATA = $CacheRoot
            $StateDirectory = Join-Path $CacheRoot 'Code\User\globalStorage'
            New-Item -Path $StateDirectory -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $StateDirectory 'state.vscdb') -ItemType File -Force | Out-Null
            $script:CacheAttempts = 0

            Mock Initialize-SqliteInterop { return $true }
            Mock Get-CachedModelRecord {
                $script:CacheAttempts++
                return [PSCustomObject]@{ Succeeded = $true; Records = @() }
            }

            $Models = @(Get-VSCodeModelCatalog)

            $script:CacheAttempts | Should -Be 1
            $Models.Count | Should -Be 0
        }
        finally
        {
            $env:APPDATA = $OriginalAppData
            Remove-Variable CacheAttempts -Scope Script -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $CacheRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Previous installation recovery' {
    BeforeEach {
        $script:RecoveryRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-recovery-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:RecoveryRoot -ItemType Directory -Force | Out-Null
        $script:CoordinatorFile = 'multi-model-engineering-council.agent.md'
    }

    AfterEach {
        Remove-Item -LiteralPath $script:RecoveryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'recovers the roster from front matter after the prose line is reworded' {
        $ExpertMap = @(
            [PSCustomObject]@{
                ExpertName = 'Claude Opus 5 Expert'
                ModelName = 'Claude Opus 5'
                LensTitle = 'Implementation and correctness'
                ReviewerNames = @('Grok 4.5 Reviewer')
            },
            [PSCustomObject]@{
                ExpertName = 'Grok 4.5 Expert'
                ModelName = 'Grok 4.5'
                LensTitle = 'Architecture and maintainability'
                ReviewerNames = @('Claude Opus 5 Reviewer')
            }
        )

        $Coordinator = New-CoordinatorAgentContent `
            -AgentName 'Multi-Model Engineering Council' `
            -ModelName 'Claude Opus 5' `
            -ExpertMap $ExpertMap `
            -CrossModelReview $true

        $Reworded = $Coordinator -replace '(?m)^- (.+) Expert running .+$', '- $1 Expert, lens withheld'
        $Reworded | Should -Not -Match 'Expert running'

        Write-Utf8File -Path (Join-Path $script:RecoveryRoot $script:CoordinatorFile) -Content $Reworded

        $Recovered = Get-PreviousCouncilConfiguration `
            -AgentDirectory $script:RecoveryRoot `
            -CoordinatorFileName $script:CoordinatorFile

        $Recovered.Models | Should -Be @('Claude Opus 5', 'Grok 4.5')
        $Recovered.CoordinatorModel | Should -Be 'Claude Opus 5'
    }

    It 'ignores a roster declared in the prompt body rather than the front matter' {
        $Planted = @(
            '---'
            'name: Multi-Model Engineering Council'
            'model: "Claude Opus 5"'
            "agents: ['Grok 4.5 Expert']"
            '---'
            ''
            'Prompt body text that a workspace can control.'
            ''
            "agents: ['GPT-5.6 Sol Expert', 'Claude Sonnet 5 Expert']"
            ''
            'model: "Injected Model"'
        ) -join [Environment]::NewLine

        Write-Utf8File -Path (Join-Path $script:RecoveryRoot $script:CoordinatorFile) -Content $Planted

        $Recovered = Get-PreviousCouncilConfiguration `
            -AgentDirectory $script:RecoveryRoot `
            -CoordinatorFileName $script:CoordinatorFile

        $Recovered.Models | Should -Be @('Grok 4.5')
        $Recovered.CoordinatorModel | Should -Be 'Claude Opus 5'
    }

    It 'treats an unterminated front matter block as no front matter at all' {
        # Without a closing delimiter there is no boundary, so trusting the block would trust the body.
        $Planted = @(
            '---'
            'name: Multi-Model Engineering Council'
            'model: "Claude Opus 5"'
            ''
            'The block above was never closed and declares no roster.'
            ''
            "agents: ['GPT-5.6 Sol Expert', 'Claude Sonnet 5 Expert']"
        ) -join [Environment]::NewLine

        Write-Utf8File -Path (Join-Path $script:RecoveryRoot $script:CoordinatorFile) -Content $Planted

        $Recovered = Get-PreviousCouncilConfiguration `
            -AgentDirectory $script:RecoveryRoot `
            -CoordinatorFileName $script:CoordinatorFile

        @($Recovered.Models) | Should -Not -Contain 'GPT-5.6 Sol'
        @($Recovered.Models) | Should -Not -Contain 'Claude Sonnet 5'
    }

    It 'ignores a roster written as prose in the body' {
        # Every coordinator this installer writes declares its roster in front matter, so a prose
        # line is only ever workspace-controlled text.
        $Planted = @(
            '---'
            'name: Multi-Model Engineering Council'
            'model: "Claude Opus 5"'
            '---'
            ''
            'Configured experts'
            ''
            '- Evil Expert running Evil, primary lens Implementation and correctness'
        ) -join [Environment]::NewLine

        Write-Utf8File -Path (Join-Path $script:RecoveryRoot $script:CoordinatorFile) -Content $Planted

        Get-PreviousCouncilConfiguration `
            -AgentDirectory $script:RecoveryRoot `
            -CoordinatorFileName $script:CoordinatorFile | Should -BeNullOrEmpty
    }
}

Describe 'Environment-dependent helpers' {

    # These were unreachable from the end-to-end tests, which always pass -SkipUpdateCheck,
    # -SkipVSCodeSetting, and an explicit roster.
    Context 'Get-VSCodeUserSettingsPath' {
        BeforeEach {
            $script:AppDataRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-appdata-$([guid]::NewGuid().ToString('N'))"
            New-Item -Path $script:AppDataRoot -ItemType Directory -Force | Out-Null
            $script:OriginalAppData = $env:APPDATA
            $env:APPDATA = $script:AppDataRoot
        }

        AfterEach {
            $env:APPDATA = $script:OriginalAppData
            Remove-Item -LiteralPath $script:AppDataRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'returns an explicit path unchanged' {
            $Explicit = Join-Path $script:AppDataRoot 'custom.json'

            Get-VSCodeUserSettingsPath -ExplicitPath $Explicit | Should -Be $Explicit
        }

        It 'prefers stable over insiders when both exist' {
            foreach ($Flavor in @('Code', 'Code - Insiders'))
            {
                $Directory = Join-Path $script:AppDataRoot "$Flavor\User"
                New-Item -Path $Directory -ItemType Directory -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $Directory 'settings.json'), '{}')
            }

            Get-VSCodeUserSettingsPath | Should -Be (Join-Path $script:AppDataRoot 'Code\User\settings.json')
        }

        It 'falls back to insiders when only insiders exists' {
            $Directory = Join-Path $script:AppDataRoot 'Code - Insiders\User'
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $Directory 'settings.json'), '{}')

            Get-VSCodeUserSettingsPath | Should -Be (Join-Path $script:AppDataRoot 'Code - Insiders\User\settings.json')
        }

        It 'returns the stable path when neither exists so the file is created there' {
            Get-VSCodeUserSettingsPath | Should -Be (Join-Path $script:AppDataRoot 'Code\User\settings.json')
        }
    }

    Context 'Select-CoordinatorModel' {
        It 'returns the only model without prompting' {
            Select-CoordinatorModel -ModelList @('Claude Opus 5') | Should -Be 'Claude Opus 5'
        }

        It 'gives up rather than looping forever on input it can never accept' {
            # A non-interactive host can return the same non-empty string indefinitely.
            Mock -CommandName 'Read-Host' -MockWith { 'not a number' }
            Mock -CommandName 'Write-Host' -MockWith { }

            { Select-CoordinatorModel -ModelList @('Claude Opus 5', 'Grok 4.5') } |
                Should -Throw '*Too many invalid coordinator selections*'

            # Asserting the count as well, because a cap raised to a huge number still throws.
            Should -Invoke -CommandName 'Read-Host' -Times 25 -Exactly
        }
    }

    Context 'Get-VSCodeStatus' {
        It 'picks the CLI name from the install folder, not from anywhere in the path' {
            # A profile or drive path containing "insiders" must not make a stable install look for
            # code-insiders.cmd and then report no CLI at all.
            $Root = Join-Path ([System.IO.Path]::GetTempPath()) "insiders-$([guid]::NewGuid().ToString('N'))"

            try
            {
                foreach ($Flavor in @('Microsoft VS Code', 'Microsoft VS Code Insiders'))
                {
                    $Bin = Join-Path $Root "$Flavor\bin"
                    New-Item -Path $Bin -ItemType Directory -Force | Out-Null
                }

                (Split-Path -Path (Join-Path $Root 'Microsoft VS Code') -Leaf) |
                    Should -Not -Match '(?i)Insiders$'

                (Split-Path -Path (Join-Path $Root 'Microsoft VS Code Insiders') -Leaf) |
                    Should -Match '(?i)Insiders$'
            }
            finally
            {
                Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'does not test the whole install path for the insiders flavor' {
            $InstallerText = [System.IO.File]::ReadAllText($script:InstallerPath)

            $InstallerText | Should -Not -Match '\$InstallRoot -match ''\(\?i\)Insiders'''
        }
    }

    Context 'Get-PublishedScriptVersion' {
        It 'extracts the version from a release tag' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith { [PSCustomObject]@{ tag_name = 'v5.7.5' } }

            Get-PublishedScriptVersion -Repository 'owner/repo' -TimeoutSeconds 5 | Should -Be '5.7.5'
        }

        It 'returns nothing rather than throwing when the network fails' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith { throw 'no network' }

            Get-PublishedScriptVersion -Repository 'owner/repo' -TimeoutSeconds 5 | Should -BeNullOrEmpty
        }

        It 'returns nothing when the tag carries no version' {
            Mock -CommandName 'Invoke-RestMethod' -MockWith { [PSCustomObject]@{ tag_name = 'latest' } }

            Get-PublishedScriptVersion -Repository 'owner/repo' -TimeoutSeconds 5 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Atomic file writes' {
    BeforeEach {
        $script:WriteTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-write-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:WriteTestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:WriteTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Test-RestoreIsSafe' {
        It 'restores when this run never wrote the file' {
            $Path = Join-Path $script:WriteTestRoot 'a.md'
            [System.IO.File]::WriteAllText($Path, 'someone else')

            Test-RestoreIsSafe -Path $Path -InstalledBytes $null | Should -BeTrue
        }

        It 'restores when the file still holds what this run wrote' {
            $Path = Join-Path $script:WriteTestRoot 'b.md'
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes('ours')
            [System.IO.File]::WriteAllBytes($Path, $Bytes)

            Test-RestoreIsSafe -Path $Path -InstalledBytes $Bytes | Should -BeTrue
        }

        It 'leaves a file that changed after this run wrote it' {
            $Path = Join-Path $script:WriteTestRoot 'c.md'
            [System.IO.File]::WriteAllText($Path, 'edited by someone else')

            Test-RestoreIsSafe -Path $Path -InstalledBytes ([System.Text.Encoding]::UTF8.GetBytes('ours')) |
                Should -BeFalse
        }

        It 'leaves a file that was deleted after this run wrote it' {
            $Path = Join-Path $script:WriteTestRoot 'missing.md'

            # Deleting is a change too, so re-creating it would undo someone's decision.
            Test-RestoreIsSafe -Path $Path -InstalledBytes ([System.Text.Encoding]::UTF8.GetBytes('ours')) |
                Should -BeFalse
        }

        It 'restores a path this run never wrote even when it is missing' {
            $Path = Join-Path $script:WriteTestRoot 'stale.md'

            Test-RestoreIsSafe -Path $Path -InstalledBytes $null | Should -BeTrue
        }
    }

    It 'leaves the original file intact when the replacement cannot complete' {
        $Target = Join-Path $script:WriteTestRoot 'agent.md'
        $Original = "original content`n"
        [System.IO.File]::WriteAllText($Target, $Original, (New-Object System.Text.UTF8Encoding($false)))
        $OriginalBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Target))

        # An exclusive handle is the deterministic way to make File.Replace fail on Windows.
        $Handle = [System.IO.File]::Open($Target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)

        try
        {
            { Write-Utf8File -Path $Target -Content 'replacement content' } |
                Should -Throw '*Atomic replacement failed*'
        }
        finally
        {
            $Handle.Dispose()
        }

        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Target)) | Should -Be $OriginalBytes

        # A failed write must not leave its scratch files behind next to the target.
        @(Get-ChildItem -LiteralPath $script:WriteTestRoot -File | Where-Object { $_.Name -ne 'agent.md' }) |
            Should -BeNullOrEmpty
    }
}

Describe 'Generated agent policy' {
    BeforeAll {
        $script:ExpertMap = @(
            [PSCustomObject]@{
                ExpertName = 'Claude Opus 5 Expert'
                ModelName = 'Claude Opus 5'
                LensTitle = 'Implementation and correctness'
                ReviewerNames = @('GPT-5.6 Sol Reviewer')
            },
            [PSCustomObject]@{
                ExpertName = 'GPT-5.6 Sol Expert'
                ModelName = 'GPT-5.6 Sol'
                LensTitle = 'Architecture and maintainability'
                ReviewerNames = @('Claude Opus 5 Reviewer')
            }
        )
    }

    It 'keeps reviewers hidden but model-invocable' {
        $Reviewer = New-ReviewerAgentContent `
            -AgentName 'GPT-5.6 Sol Reviewer' `
            -ModelName 'GPT-5.6 Sol'

        $Reviewer | Should -Match '(?m)^user-invocable: false\r?$'
        $Reviewer | Should -Match '(?m)^disable-model-invocation: false\r?$'
        $Reviewer | Should -Not -Match "tools:\s*\[[^\]]*'agent'"

        # A reviewer that substitutes its own target defeats the point of a targeted challenge.
        $Reviewer | Should -Match 'If the expert named a target, attack that first'
    }

    It 'keeps experts hidden but model-invocable' {
        $Expert = New-ExpertAgentContent `
            -AgentName 'Claude Opus 5 Expert' `
            -ModelName 'Claude Opus 5' `
            -LensTitle 'Implementation and correctness' `
            -LensFocus @('root cause analysis') `
            -ReviewerNames @('GPT-5.6 Sol Reviewer') `
            -CoordinatorName 'Multi-Model Engineering Council' `
            -CrossModelReview $true

        $Expert | Should -Match '(?m)^user-invocable: false\r?$'
        $Expert | Should -Match '(?m)^disable-model-invocation: false\r?$'
        $Expert | Should -Match 'NESTED REVIEW: REQUIRED \| AUTHORIZED \| SKIP'

        # An expert investigates and proposes. The coordinator owns every file edit, so an expert
        # gaining edit or execute would break that boundary silently.
        $Expert | Should -Match "tools: \['agent', 'read', 'search', 'web'\]"
        $Expert | Should -Not -Match "tools: \[[^\]]*'edit'"
        $Expert | Should -Not -Match "tools: \[[^\]]*'execute'"
    }

    It 'protects the coordinator and requires Tier 5 leaf reviews' {
        $Coordinator = New-CoordinatorAgentContent `
            -AgentName 'Multi-Model Engineering Council' `
            -ModelName 'Claude Opus 5' `
            -ExpertMap $script:ExpertMap `
            -CrossModelReview $true

        $Coordinator | Should -Match '(?m)^user-invocable: true\r?$'
        $Coordinator | Should -Match '(?m)^disable-model-invocation: true\r?$'
        $Coordinator | Should -Match "tools: \['agent', 'read', 'search', 'edit', 'execute', 'web', 'todo'\]"
        $Coordinator | Should -Match 'Use REQUIRED for both cross-model Tier 3 branches and every Tier 5 branch.'
        $Coordinator | Should -Match 'up to 2 parallel expert calls plus 2 leaf-reviewer calls'
    }

    It 'rejects an agent whose tool list drifted from the expectation' {
        $Reviewer = New-ReviewerAgentContent `
            -AgentName 'GPT-5.6 Sol Reviewer' `
            -ModelName 'GPT-5.6 Sol'

        $Record = [PSCustomObject]@{
            FileName = 'mm-reviewer-drift.agent.md'
            Content = $Reviewer -replace "tools: \['read', 'search', 'web'\]", "tools: ['read', 'search', 'web', 'execute']"
            ExpectedName = 'GPT-5.6 Sol Reviewer'
            ExpectedModel = 'GPT-5.6 Sol'
            ExpectedUserInvocable = $false
            ExpectedDisableModelInvocation = $false
            ExpectedTools = $script:ReviewerAgentTools
            ExpectedAgents = @()
            MustNotDelegate = $true
            MustNotSelfReview = $false
        }

        { Test-GeneratedAgentFile -Record $Record } | Should -Throw '*Expected tool list*'
    }
}

Describe 'VS Code settings mutation' {
    BeforeEach {
        $script:SettingsTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-settings-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:SettingsTestRoot -ItemType Directory -Force | Out-Null
        $script:SettingName = 'chat.subagents.allowInvocationsFromSubagents'
        $script:Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    }

    AfterEach {
        Remove-Item -LiteralPath $script:SettingsTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'does not rewrite or back up an existing true value' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $Original = "{`r`n  `"$script:SettingName`": true,`r`n  `"editor.fontSize`": 14`r`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        $Changed = Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath

        $Changed | Should -BeFalse
        (Read-Utf8File -Path $SettingsPath) | Should -BeExactly $Original
        Test-Path -LiteralPath $BackupPath | Should -BeFalse
    }

    It 'enables the setting in a file whose keys differ only by case' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'

        # VS Code keeps the last of these; ConvertFrom-Json cannot represent them as properties.
        $Original = "{`n  `"terminal.integrated.env.windows`": { `"Path`": `"a`", `"PATH`": `"b`" }`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath | Should -BeTrue
        (Read-Utf8File -Path $SettingsPath) | Should -Match ([regex]::Escape($script:SettingName))
    }

    It 'does not claim an already-enabled file is unparseable when keys differ only by case' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $Original = "{`n  `"a`": 1,`n  `"A`": 2,`n  `"$script:SettingName`": true`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        $Output = Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath 6>&1

        ($Output -join "`n") | Should -Not -Match 'could not be parsed'
        (Read-Utf8File -Path $SettingsPath) | Should -BeExactly $Original
    }

    It 'warns instead of reporting success when an already-enabled file cannot be parsed' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $Original = "{`n  `"$script:SettingName`": true,`n  `"broken`": [1,2,`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        # The value is already correct, so nothing is written, but VS Code will ignore the whole file.
        $Output = Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath 6>&1

        ($Output | Where-Object { $_ -is [bool] }) | Should -BeFalse
        ($Output -join "`n") | Should -Match 'could not be parsed'
        (Read-Utf8File -Path $SettingsPath) | Should -BeExactly $Original
        Test-Path -LiteralPath $BackupPath | Should -BeFalse
    }

    It 'inserts a root value without changing a nested lookalike' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $Original = "{`n  `"nested`": { `"$script:SettingName`": false },`n  `"editor.fontSize`": 14`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath | Should -BeTrue
        $Parsed = ConvertFrom-JsoncText -Text (Read-Utf8File -Path $SettingsPath)

        (Get-PropertyValue -InputObject $Parsed -Name $script:SettingName) | Should -BeTrue
        (Get-PropertyValue -InputObject $Parsed.nested -Name $script:SettingName) | Should -BeFalse
    }

    It 'rejects duplicate root values without mutation' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $Original = "{ `"$script:SettingName`": false, `"$script:SettingName`": true }"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, $script:Utf8WithoutBom)

        { Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath } |
            Should -Throw '*appears more than once*'

        (Read-Utf8File -Path $SettingsPath) | Should -BeExactly $Original
    }

    It 'rejects invalid UTF-8 without backup or mutation' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        $OriginalBytes = [byte[]](0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0x80, 0x22, 0x7D)
        [System.IO.File]::WriteAllBytes($SettingsPath, $OriginalBytes)

        { Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath } |
            Should -Throw '*not valid UTF-8*'

        [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($SettingsPath)) |
            Should -Be ([Convert]::ToBase64String($OriginalBytes))
        Test-Path -LiteralPath $BackupPath | Should -BeFalse
    }

    It 'enables the setting in an empty or whitespace-only file' -ForEach @(
        @{ Label = 'empty'; Text = '' }
        @{ Label = 'whitespace'; Text = "  `r`n  " }
    ) {
        $SettingsPath = Join-Path $script:SettingsTestRoot "settings-$Label.json"
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        [System.IO.File]::WriteAllText($SettingsPath, $Text, $script:Utf8WithoutBom)

        Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath | Should -BeTrue

        $Parsed = ConvertFrom-JsoncText -Text (Read-Utf8File -Path $SettingsPath)
        (Get-PropertyValue -InputObject $Parsed -Name $script:SettingName) | Should -BeTrue
    }

    It 'does not report a write attempt when the value is already true' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        [System.IO.File]::WriteAllText($SettingsPath, "{ `"$script:SettingName`": true }", $script:Utf8WithoutBom)
        $WriteState = @{ Attempted = $false; WrittenContent = $null }

        Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath -WriteState $WriteState |
            Should -BeFalse

        # Rollback keys off this flag, so a false positive here overwrites a file the installer never touched.
        $WriteState.Attempted | Should -BeFalse
        $WriteState.WrittenContent | Should -BeNullOrEmpty
    }

    It 'reports the exact written content when it does change the file' {
        $SettingsPath = Join-Path $script:SettingsTestRoot 'settings.json'
        $BackupPath = Join-Path $script:SettingsTestRoot 'backup'
        [System.IO.File]::WriteAllText($SettingsPath, "{ `"editor.fontSize`": 14 }", $script:Utf8WithoutBom)
        $WriteState = @{ Attempted = $false; WrittenContent = $null }

        Set-VSCodeNestedSubagentsSetting -SettingsPath $SettingsPath -BackupDirectory $BackupPath -WriteState $WriteState |
            Should -BeTrue

        $WriteState.Attempted | Should -BeTrue
        $WriteState.WrittenContent | Should -BeExactly (Read-Utf8File -Path $SettingsPath)
    }
}

Describe 'Backup retention' {
    BeforeEach {
        $script:BackupTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-backup-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:BackupTestRoot -ItemType Directory -Force | Out-Null

        foreach ($Index in 1..20)
        {
            New-Item -Path (Join-Path $script:BackupTestRoot ('v5_20260101_{0:D9}' -f $Index)) -ItemType Directory -Force | Out-Null
        }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:BackupTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'counts the current backup against the retention cap' {
        $Current = Join-Path $script:BackupTestRoot 'v5_20260101_000000020'

        Remove-ExpiredBackup -BackupRoot $script:BackupTestRoot -CurrentBackupDirectory $Current -KeepCount 10 6>$null

        @(Get-ChildItem -LiteralPath $script:BackupTestRoot -Directory).Count | Should -Be 10
        Test-Path -LiteralPath $Current | Should -BeTrue
    }

    It 'keeps the retention count when this run created no backup' {
        $Absent = Join-Path $script:BackupTestRoot 'v5_20260101_000000099'

        Remove-ExpiredBackup -BackupRoot $script:BackupTestRoot -CurrentBackupDirectory $Absent -KeepCount 10 6>$null

        @(Get-ChildItem -LiteralPath $script:BackupTestRoot -Directory).Count | Should -Be 10
    }

    It 'leaves directories that do not match the backup pattern' {
        New-Item -Path (Join-Path $script:BackupTestRoot 'my-own-notes') -ItemType Directory -Force | Out-Null

        Remove-ExpiredBackup `
            -BackupRoot $script:BackupTestRoot `
            -CurrentBackupDirectory (Join-Path $script:BackupTestRoot 'v5_20260101_000000020') `
            -KeepCount 10 6>$null

        Test-Path -LiteralPath (Join-Path $script:BackupTestRoot 'my-own-notes') | Should -BeTrue
    }

    It 'defaults to the retention count stated in the documentation' {
        $script:BackupRetentionCount | Should -Be 10
    }
}

Describe 'End-to-end workspace install' {
    BeforeEach {
        $script:InstallTestRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "council-install-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $script:InstallTestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:InstallTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'generates and validates a two-model roster with non-ASCII content' {
        $UnicodeModel = 'G' + [char]0x00E9 + 'mini Test'

        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models $UnicodeModel, 'Grok 4.5' | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        $AgentFiles = @(Get-ChildItem -LiteralPath $AgentDirectory -Filter '*.agent.md' -File)
        $Workers = @(Get-ChildItem -LiteralPath $AgentDirectory -Filter 'mm-*.agent.md' -File)
        $CoordinatorPath = Join-Path $AgentDirectory 'multi-model-engineering-council.agent.md'

        $AgentFiles.Count | Should -Be 5

        foreach ($Worker in $Workers)
        {
            Read-Utf8File -Path $Worker.FullName | Should -Match '(?m)^disable-model-invocation: false\r?$'
        }

        $Coordinator = Read-Utf8File -Path $CoordinatorPath
        $Coordinator | Should -Match '(?m)^disable-model-invocation: true\r?$'
        $Coordinator | Should -Match 'up to 2 parallel expert calls plus 2 leaf-reviewer calls'
        $Coordinator | Should -Match ([regex]::Escape($UnicodeModel))
    }

    It 'leaves unchanged agent files untouched on a repeated install' {
        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models 'Claude Opus 5', 'Grok 4.5' | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        $Before = @{}

        foreach ($AgentFile in @(Get-ChildItem -LiteralPath $AgentDirectory -Filter '*.agent.md' -File))
        {
            $Before[$AgentFile.Name] = $AgentFile.LastWriteTimeUtc
        }

        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models 'Claude Opus 5', 'Grok 4.5' | Out-Null

        $After = @(Get-ChildItem -LiteralPath $AgentDirectory -Filter '*.agent.md' -File)
        $After.Count | Should -Be $Before.Count

        foreach ($AgentFile in $After)
        {
            $AgentFile.LastWriteTimeUtc | Should -Be $Before[$AgentFile.Name]
        }
    }

    It 'rewrites a file whose bytes drifted even though its text did not' {
        $Arguments = @{
            Scope = 'Workspace'
            WorkspacePath = $script:InstallTestRoot
            NonInteractive = $true
            SkipUpdateCheck = $true
            SkipVSCodeSetting = $true
            Models = @('Claude Opus 5', 'Grok 4.5')
        }

        & $script:InstallerPath @Arguments | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        $Target = Join-Path $AgentDirectory 'multi-model-engineering-council.agent.md'
        $Text = Read-Utf8File -Path $Target

        # A BOM decodes to the same text, so a skip decision based on text instead of bytes would
        # leave front matter VS Code cannot parse.
        [System.IO.File]::WriteAllText($Target, $Text, (New-Object System.Text.UTF8Encoding($true)))
        [System.IO.File]::ReadAllBytes($Target)[0] | Should -Be 0xEF

        & $script:InstallerPath @Arguments | Out-Null

        [System.IO.File]::ReadAllBytes($Target)[0] | Should -Not -Be 0xEF
        Read-Utf8File -Path $Target | Should -BeExactly $Text
    }

    It 'generates a coherent single-model council' {
        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models 'Claude Opus 5' | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        @(Get-ChildItem -LiteralPath $AgentDirectory -Filter '*.agent.md' -File).Count | Should -Be 3

        $Coordinator = Read-Utf8File -Path (Join-Path $AgentDirectory 'multi-model-engineering-council.agent.md')
        $Expert = Read-Utf8File -Path (Join-Path $AgentDirectory 'mm-expert-claude-opus-5.agent.md')

        # Tiers 2 and 4 need a second model, so a one-model roster must not advertise them.
        $Coordinator | Should -Match '(?m)^### Tier 2 - Two experts in parallel\r?\n\r?\nUnavailable\.'
        $Coordinator | Should -Match '(?m)^### Tier 4 - Parallel engineering team\r?\n\r?\nUnavailable\.'

        # The single-model Tier 3 fallback skips nested review, so it cannot be priced as including it.
        $Coordinator | Should -Not -Match 'roughly four model invocations'
        $Coordinator | Should -Not -Match 'up to 1 parallel expert calls'
        $Coordinator | Should -Not -Match '1 leaf-reviewer calls'

        # The expert and the coordinator have to state the same nested-review policy.
        $Expert | Should -Match 'The single-model Tier 3 fallback uses SKIP\.'
        $Expert | Should -Not -Match 'Tier 3 and Tier 5 use REQUIRED'
    }

    It 'pins the Tier 5 brief contract' -ForEach @(
        @{ Label = 'one model'; Models = @('Claude Opus 5') }
        @{ Label = 'two models'; Models = @('Claude Opus 5', 'Grok 4.5') }
    ) {
        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models $Models | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        $Coordinator = Read-Utf8File -Path (Join-Path $AgentDirectory 'multi-model-engineering-council.agent.md')
        $Expert = Read-Utf8File -Path (Join-Path $AgentDirectory 'mm-expert-claude-opus-5.agent.md')

        # Tier 5 dispatches before any analysis exists, so the coordinator names a class of claim.
        # The expert never receives the coordinator's explanation of that carve-out, so its own schema
        # has to admit the shape or it will read a REQUIRED directive as malformed and skip the review.
        $Coordinator | Should -Match 'TARGET: the single assumption your conclusion most depends on'
        $Expert | Should -Match 'a class of claim at Tier 5, or NONE'
        $Expert | Should -Match 'Never downgrade it to SKIP\.'
        $Expert | Should -Match 'Tier 5 uses? REQUIRED'

        # Only the verbatim override reaches the expert, so the lens constraint has to live inside it
        # rather than in the coordinator-only prose that follows.
        $Coordinator | Should -Match 'not permission to leave that lens'
        $Coordinator | Should -Not -Match 'cross-domain enhancements'
    }

    It 'tells the coordinator to close with a TL;DR' -ForEach @(
        @{ Label = 'one model'; Models = @('Claude Opus 5') }
        @{ Label = 'two models'; Models = @('Claude Opus 5', 'Grok 4.5') }
    ) {
        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models $Models | Out-Null

        $Coordinator = Read-Utf8File -Path (Join-Path $script:InstallTestRoot '.github\agents\multi-model-engineering-council.agent.md')

        $Coordinator | Should -Match '(?m)^### TL;DR\r?$'
    }

    It 'gives every role the same evidence ranking' {
        & $script:InstallerPath `
            -Scope Workspace `
            -WorkspacePath $script:InstallTestRoot `
            -NonInteractive `
            -SkipUpdateCheck `
            -SkipVSCodeSetting `
            -Models 'Claude Opus 5', 'Grok 4.5' | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'

        # Written out rather than derived from $EvidenceHierarchy: building the expectation from the
        # constant under test would accept any reworded item.
        $Expected = @(
            '1. Repository source code'
            '2. Reproducible tests'
            '3. Runtime, compiler, or interpreter behavior'
            '4. Official documentation'
            '5. API specifications'
            '6. Platform diagnostics and logs'
            '7. Logical consistency'
            '8. Established engineering practice'
        ) -join "`n"

        foreach ($FileName in @(
                'multi-model-engineering-council.agent.md',
                'mm-expert-claude-opus-5.agent.md',
                'mm-reviewer-claude-opus-5.agent.md'))
        {
            $Text = (Read-Utf8File -Path (Join-Path $AgentDirectory $FileName)) -replace '\r', ''

            $Text | Should -BeLike "*$Expected*" -Because "$FileName must render the shared evidence ranking"
        }
    }

    It 'restores the settings file when activation fails after it was written' {
        $SettingsPath = Join-Path $script:InstallTestRoot 'settings.json'
        $Original = "{`n  `"editor.fontSize`": 14`n}"
        [System.IO.File]::WriteAllText($SettingsPath, $Original, (New-Object System.Text.UTF8Encoding($false)))

        # A directory where an agent file belongs makes the write fail after the settings step,
        # which is the only way to reach the rollback from outside the script.
        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        New-Item -Path (Join-Path $AgentDirectory 'multi-model-engineering-council.agent.md') -ItemType Directory -Force | Out-Null

        $LogPath = Join-Path $script:InstallTestRoot 'install.log'
        $Failure = $null

        try
        {
            # Redirected to a file because an assignment would be discarded when the run throws.
            & $script:InstallerPath `
                -Scope Workspace `
                -WorkspacePath $script:InstallTestRoot `
                -NonInteractive `
                -SkipUpdateCheck `
                -VSCodeSettingsPath $SettingsPath `
                -Models 'Claude Opus 5' *> $LogPath
        }
        catch
        {
            $Failure = $_
        }

        $Failure | Should -Not -BeNullOrEmpty

        # Without this the restore assertion would also pass for a run that failed before the
        # settings were ever written, which would prove nothing about the rollback.
        [System.IO.File]::ReadAllText($LogPath) | Should -Match 'Enabled VS Code setting'

        # The setting was enabled and then the install failed, so the original file must come back.
        (Read-Utf8File -Path $SettingsPath) | Should -BeExactly $Original
    }

    It 'does not delete stale files through a linked agent directory' {
        $Outside = Join-Path $script:InstallTestRoot 'outside'
        New-Item -Path $Outside -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:InstallTestRoot '.github') -ItemType Directory -Force | Out-Null

        $Link = Join-Path $script:InstallTestRoot '.github\agents'
        New-Item -Path $Link -ItemType Junction -Target $Outside -ErrorAction Stop | Out-Null

        try
        {
            # Matches the stale pattern, but it lives outside the workspace the user named.
            $Foreign = Join-Path $Outside 'mm-expert-foreign.agent.md'
            [System.IO.File]::WriteAllText($Foreign, 'not ours to delete')

            & $script:InstallerPath `
                -Scope Workspace `
                -WorkspacePath $script:InstallTestRoot `
                -NonInteractive `
                -SkipUpdateCheck `
                -SkipVSCodeSetting `
                -Models 'Claude Opus 5' | Out-Null

            Test-Path -LiteralPath $Foreign | Should -BeTrue
            [System.IO.File]::ReadAllText($Foreign) | Should -BeExactly 'not ours to delete'
        }
        finally
        {
            if (Test-Path -LiteralPath $Link)
            {
                [System.IO.Directory]::Delete($Link, $false)
            }
        }
    }

    It 'does not delete a lookalike file it did not write' -ForEach @(
        @{
            Label = 'unrelated front matter'
            Text = "---`nname: Something Else`n---`n`nHand written."
        }
        @{
            # The body of an agent file may legitimately quote front-matter syntax as an example,
            # so matching anywhere in the file would condemn this one.
            Label = 'body quotes front matter'
            Text = "# Notes`n`nAn agent file starts like this:`n`nname: My Custom Expert`ntarget: vscode`nuser-invocable: false`n"
        }
    ) {
        $Arguments = @{
            Scope = 'Workspace'
            WorkspacePath = $script:InstallTestRoot
            NonInteractive = $true
            SkipUpdateCheck = $true
            SkipVSCodeSetting = $true
            Models = @('Claude Opus 5', 'Grok 4.5')
        }

        & $script:InstallerPath @Arguments | Out-Null

        $AgentDirectory = Join-Path $script:InstallTestRoot '.github\agents'
        $Impostor = Join-Path $AgentDirectory 'mm-expert-handwritten.agent.md'
        [System.IO.File]::WriteAllText($Impostor, $Text)

        # Reinstalling with one model makes the second model's files stale, which is what triggers
        # the sweep that used to select purely on the file name.
        $Arguments.Models = @('Claude Opus 5')
        & $script:InstallerPath @Arguments | Out-Null

        Test-Path -LiteralPath $Impostor | Should -BeTrue
        [System.IO.File]::ReadAllText($Impostor) | Should -BeExactly $Text
        Test-Path -LiteralPath (Join-Path $AgentDirectory 'mm-expert-grok-4-5.agent.md') | Should -BeFalse
    }

    It 'refuses a workspace path that is a file rather than a directory' {
        $FilePath = Join-Path $script:InstallTestRoot 'not-a-directory.txt'
        [System.IO.File]::WriteAllText($FilePath, 'x')

        {
            & $script:InstallerPath `
                -Scope Workspace `
                -WorkspacePath $FilePath `
                -NonInteractive `
                -SkipUpdateCheck `
                -SkipVSCodeSetting `
                -Models 'Claude Opus 5'
        } | Should -Throw '*not an existing directory*'
    }
}
