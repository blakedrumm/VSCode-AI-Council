BeforeAll {
    $script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:GeneratorPath = Join-Path -Path $script:RepositoryRoot -ChildPath '.github/scripts/New-ReleaseNotes.ps1'
    $script:ChangelogPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'CHANGELOG.md'
    $script:InstallerPath = Join-Path -Path $script:RepositoryRoot -ChildPath 'Install-VSCodeCopilotCouncil-v5.ps1'

    $script:OutputRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("notes-tests-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $script:OutputRoot -ItemType Directory -Force

    function script:New-Notes
    {
        param
        (
            [string]$Version,
            [string]$Additions = ''
        )

        $outputPath = Join-Path -Path $script:OutputRoot -ChildPath ([guid]::NewGuid().ToString('N') + '.md')

        $null = & $script:GeneratorPath `
            -Version $Version `
            -Repository 'blakedrumm/VSCode-AI-Council' `
            -Additions $Additions `
            -ChangelogPath $script:ChangelogPath `
            -OutputPath $outputPath

        return [IO.File]::ReadAllText($outputPath)
    }
}

AfterAll {
    if ($script:OutputRoot -and (Test-Path -LiteralPath $script:OutputRoot))
    {
        Remove-Item -LiteralPath $script:OutputRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Release notes generation' {

    It 'uses the changelog section for the version instead of a placeholder' {
        $notes = script:New-Notes -Version '5.7.3'

        $notes | Should -Not -Match 'Released VS Code AI Council version'
        $notes | Should -Match 'Rollback could destroy a settings file'
    }

    It 'stops at the next version heading so sections do not bleed together' {
        $notes = script:New-Notes -Version '5.7.2'

        $notes | Should -Match 'Post-install validation never checked'
        $notes | Should -Not -Match 'Rollback could destroy a settings file'
    }

    It 'promotes changelog subheadings one level under the release title' {
        $notes = script:New-Notes -Version '5.7.3'

        $notes | Should -Match '(?m)^## Fixed\r?$'
        $notes | Should -Not -Match '(?m)^### Fixed\r?$'
    }

    It 'lets explicit additions override the changelog' {
        $notes = script:New-Notes -Version '5.7.3' -Additions "First item`nSecond item"

        $notes | Should -Match '(?m)^- First item\r?$'
        $notes | Should -Match '(?m)^- Second item\r?$'
        $notes | Should -Not -Match 'Rollback could destroy a settings file'
    }

    It 'falls back to the placeholder when no changelog section matches' {
        $notes = script:New-Notes -Version '99.99.99'

        $notes | Should -Match 'Released VS Code AI Council version 99\.99\.99\.'
    }

    It 'always includes the install instructions and the download badge' {
        $notes = script:New-Notes -Version '5.7.3'

        $notes | Should -Match '(?m)^## Install\r?$'
        $notes | Should -Match 'Invoke-WebRequest -Uri'
        $notes | Should -Match 'img\.shields\.io/github/downloads'
    }

    # Guards the defect this suite was written for: a release whose notes would be a bare placeholder.
    It 'has a changelog section for the version the installer currently reports' {
        $installerText = [IO.File]::ReadAllText($script:InstallerPath)
        $versionMatch = [regex]::Match($installerText, "\`$ScriptVersion\s*=\s*'(?<Version>\d+\.\d+\.\d+)'")
        $versionMatch.Success | Should -BeTrue

        $currentVersion = $versionMatch.Groups['Version'].Value
        $notes = script:New-Notes -Version $currentVersion

        $notes | Should -Not -Match 'Released VS Code AI Council version'
    }
}
