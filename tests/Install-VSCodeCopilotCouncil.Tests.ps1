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
}
