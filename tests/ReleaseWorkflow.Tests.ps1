BeforeAll {
    Set-StrictMode -Version Latest
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ReleaseWorkflowPath = Join-Path -Path $script:RepositoryRoot -ChildPath '.github/workflows/release.yml'
    $script:ReleaseWorkflow = [System.IO.File]::ReadAllText($script:ReleaseWorkflowPath)
    $script:ValidateWorkflow = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github/workflows/validate.yml'))

    # Parsed by indentation rather than with a YAML module, so the suite gains no dependency that
    # CI would then have to pin.
    function script:Get-JobBlock
    {
        param
        (
            [string]$Name
        )

        $Lines = $script:ReleaseWorkflow -split '\r?\n'
        $Collecting = $false
        $Block = New-Object System.Collections.Generic.List[string]

        foreach ($Line in $Lines)
        {
            if ($Line -match '^  (?<job>[A-Za-z_][A-Za-z0-9_-]*):\s*$')
            {
                if ($Collecting)
                {
                    break
                }

                $Collecting = $Matches['job'] -eq $Name
                continue
            }

            if ($Collecting)
            {
                $Block.Add($Line)
            }
        }

        return ($Block -join "`n")
    }
}

Describe 'Release workflow structure' {

    It 'defines the three jobs that separate building from publishing' {
        foreach ($Job in @('build_test', 'publish_github', 'publish_sftp'))
        {
            script:Get-JobBlock -Name $Job | Should -Not -BeNullOrEmpty -Because "$Job must exist"
        }
    }

    It 'builds and tests without write permission or secrets' {
        $Block = script:Get-JobBlock -Name 'build_test'

        $Block | Should -Match '(?m)^\s*contents: read\s*$'
        $Block | Should -Not -Match '(?m)^\s*contents: write\s*$'
        $Block | Should -Not -Match 'secrets\.'
    }

    It 'disables persisted checkout credentials in both workflows' {
        foreach ($Workflow in @($script:ReleaseWorkflow, $script:ValidateWorkflow))
        {
            $Workflow | Should -Match '(?m)uses: actions/checkout@[^\r\n]+\r?\n\s+with:\r?\n(?:\s+[^\r\n]+\r?\n)*?\s+persist-credentials: false'
        }
    }

    It 'selects PSGallery explicitly for every CI module installation' {
        foreach ($Workflow in @($script:ReleaseWorkflow, $script:ValidateWorkflow))
        {
            $Installs = [regex]::Matches($Workflow, '(?m)^\s*Install-Module[^\r\n]+')
            $Installs.Count | Should -BeGreaterThan 0
            foreach ($Install in $Installs)
            {
                $Install.Value | Should -Match '-Repository PSGallery(?:\s|$)'
            }
        }
    }

    It 'keeps SFTP token permissions empty and serializes release publication' {
        script:Get-JobBlock -Name 'publish_sftp' | Should -Match '(?m)^\s*permissions: \{\}\s*$'
        $script:ReleaseWorkflow | Should -Match '(?m)^\s*cancel-in-progress: false\s*$'
    }

    It 'publishes without checking out or executing repository code' {
        $Block = script:Get-JobBlock -Name 'publish_github'

        # The whole point of the split: this job holds the token, so it must not run repo code.
        $Block | Should -Not -Match 'actions/checkout'
        $Block | Should -Not -Match '\.github/scripts'
        $Block | Should -Match '(?m)^\s*contents: write\s*$'
        $Block | Should -Match 'needs: build_test'
    }

    It 'verifies the candidate against the commit before publishing' {
        $Block = script:Get-JobBlock -Name 'publish_github'

        $Block | Should -Match 'contents/Install-VSCodeCopilotCouncil-v5\.ps1\?ref='
        $Block | Should -Match 'does not match Install-VSCodeCopilotCouncil-v5\.ps1 at commit'
        $Block | Should -Match 'git/ref/tags/'
        $Block | Should -Match 'DEFAULT_BRANCH'
    }

    It 'checks containment against the default branch rather than the dispatching branch' {
        $Block = script:Get-JobBlock -Name 'publish_github'

        $Block | Should -Not -Match 'GITHUB_REF_NAME'
        $Block | Should -Match 'github\.event\.repository\.default_branch'
    }

    It 'refuses to republish an existing version' {
        $Block = script:Get-JobBlock -Name 'publish_github'

        $Block | Should -Match 'already exists'
        $Block | Should -Not -Match '--clobber'
    }

    It 'keeps the SFTP credentials out of every other job' {
        $Sftp = script:Get-JobBlock -Name 'publish_sftp'
        $Sftp | Should -Match 'secrets\.SFTP_PRIVATE_KEY'

        foreach ($Job in @('build_test', 'publish_github'))
        {
            script:Get-JobBlock -Name $Job | Should -Not -Match 'SFTP_'
        }
    }

    It 'promotes SFTP uploads by rename rather than by deleting the live file' {
        $Block = script:Get-JobBlock -Name 'publish_sftp'

        $Block | Should -Match 'rename '
        $Block | Should -Not -Match '-rm "'
    }

    It 'pins every action to a commit rather than a moving tag' {
        # Each pin carries a trailing "# vX.Y.Z" comment, so the reference stops at the first space.
        $Uses = [regex]::Matches($script:ReleaseWorkflow, '(?m)^\s*uses:\s*(?<ref>[^\s#]+)')
        $Uses.Count | Should -BeGreaterThan 0

        foreach ($Use in $Uses)
        {
            $Use.Groups['ref'].Value | Should -Match '@[0-9a-f]{40}$'
        }
    }
}

Describe 'Weekly model workflow structure' {
    BeforeAll {
        $script:ModelWorkflow = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github/workflows/update-models.yml'))
    }

    It 'runs weekly and on demand, not from untrusted pull requests' {
        $script:ModelWorkflow | Should -Match "cron: '23 9 \* \* 1'"
        $script:ModelWorkflow | Should -Match '(?m)^  workflow_dispatch:'
        $script:ModelWorkflow | Should -Not -Match 'pull_request|pull_request_target'
        $script:ModelWorkflow | Should -Match 'github\.ref == format'
        $script:ModelWorkflow | Should -Match 'cancel-in-progress: false'
    }

    It 'checks real public data then tests both supported PowerShell editions' {
        $script:ModelWorkflow | Should -Match 'Update-ModelRecommendation\.ps1 -Source GitHubDocs -Update'
        $script:ModelWorkflow | Should -Match 'Update-ModelRecommendation\.ps1 -Source GitHubDocs\r?\n'
        $script:ModelWorkflow | Should -Match 'shell: powershell'
        $script:ModelWorkflow | Should -Match 'shell: pwsh'
        @([regex]::Matches($script:ModelWorkflow, "Invoke-Pester -Path './tests' -CI")).Count | Should -Be 2
        $script:ModelWorkflow | Should -Match 'Invoke-ScriptAnalyzer'
        $script:ModelWorkflow | Should -Not -Match 'AllowReferenceContraction'
    }

    It 'separates validation from publication and does not run the candidate with write credentials' {
        $Refresh = [regex]::Match($script:ModelWorkflow, '(?s)  refresh:.*?(?=\r?\n  publish:)').Value
        $Publish = [regex]::Match($script:ModelWorkflow, '(?s)  publish:.*').Value
        $Refresh | Should -Match 'contents: read'
        $Refresh | Should -Match 'persist-credentials: false'
        $Refresh | Should -Not -Match 'contents: write|GH_TOKEN|secrets\.'
        $Publish | Should -Match 'needs: refresh'
        $Publish | Should -Match "if: needs.refresh.outputs.changed == 'true'"
        $Publish | Should -Match 'contents: write'
        $Publish | Should -Not -Match 'actions/checkout|Import-Module|Invoke-Expression|\.github/scripts/'
    }

    It 'publishes only the allowed files without overwriting concurrent commits' {
        $script:ModelWorkflow | Should -Match 'Unexpected changed file'
        $script:ModelWorkflow | Should -Match 'Unexpected artifact contents'
        $script:ModelWorkflow | Should -Match '\$head\.object\.sha -cne \$env:SOURCE_COMMIT'
        $script:ModelWorkflow | Should -Match 'force = \$false'
        $script:ModelWorkflow | Should -Not -Match '--force|force = \$true'
        $script:ModelWorkflow | Should -Match 'include-hidden-files: true'
    }

    It 'pins actions and module installations' {
        foreach ($Use in [regex]::Matches($script:ModelWorkflow, '(?m)^\s*uses:\s*(?<ref>[^\s#]+)'))
        {
            $Use.Groups['ref'].Value | Should -Match '@[0-9a-f]{40}$'
        }
        foreach ($Install in [regex]::Matches($script:ModelWorkflow, '(?m)^\s*Install-Module[^\r\n]+'))
        {
            $Install.Value | Should -Match '-Repository PSGallery(?:\s|$)'
            $Install.Value | Should -Match '-RequiredVersion [0-9]+\.[0-9]+\.[0-9]+'
        }
    }

    It 'contains syntactically valid PowerShell in every inline step' {
        $Steps = [regex]::Matches($script:ModelWorkflow, '(?m)^        run: \|\r?\n(?<Body>(?:^          [^\r\n]*\r?\n|^\r?\n)+)')
        $Steps.Count | Should -Be 6
        foreach ($Step in $Steps)
        {
            $Tokens = $null
            $Errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($Step.Groups['Body'].Value, [ref]$Tokens, [ref]$Errors)
            @($Errors).Count | Should -Be 0 -Because (@($Errors | ForEach-Object { $_.Message }) -join '; ')
        }
    }
}
