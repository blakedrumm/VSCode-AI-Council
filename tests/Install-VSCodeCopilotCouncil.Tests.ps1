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
        'Restore-FileStateSnapshot',
        'Backup-ExistingFile',
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
        'Test-AgentFile',
        'Test-GeneratedAgentFile'
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
    foreach ($ConstantName in @('ReviewerAgentTools', 'ExpertAgentTools', 'CoordinatorAgentTools', 'LensCatalog', 'MaxModelCount'))
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
}
