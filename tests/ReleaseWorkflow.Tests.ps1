BeforeAll {
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:ReleaseWorkflowPath = Join-Path -Path $script:RepositoryRoot -ChildPath '.github/workflows/release.yml'
    $script:ReleaseWorkflow = [System.IO.File]::ReadAllText($script:ReleaseWorkflowPath)

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
