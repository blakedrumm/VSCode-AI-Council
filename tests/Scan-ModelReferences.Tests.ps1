BeforeAll {
    Set-StrictMode -Version Latest
    $script:ScannerPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.github/scripts/Scan-ModelReferences.ps1'
    $script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)
}

Describe 'Alias application' {
    BeforeEach {
        $script:ScanRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [System.IO.Directory]::CreateDirectory($script:ScanRoot) | Out-Null
        $script:RegistryPath = Join-Path $script:ScanRoot 'Install-VSCodeCopilotCouncil-v5.ps1'
        $script:UsagePath = Join-Path $script:ScanRoot 'usage.ps1'
        $script:Registry = @'
$DefaultModelCatalog = @('Old Model', 'Second Model')
$DefaultModels = @('Old Model')
$RoleModelRegistry = [ordered]@{}
$ModelAliasMap = [ordered]@{ 'Old Model' = 'New Model'; 'Second Model' = 'Final Model' }
$ModelLifecycle = [ordered]@{}
'@
        [System.IO.File]::WriteAllText($script:RegistryPath, $script:Registry, $script:Utf8)
    }

    It 'changes literal references but leaves comments and the alias registry intact' {
        $Source = @(
            '# Old Model'
            "`$Name = 'Old Model' # Old Model"
            "`$Other = 'Second Model'"
            "`$Template = @'"
            'Old Model'
            'Second Model'
            "'@"
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($script:UsagePath, $Source, $script:Utf8)

        & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null

        $Updated = [System.IO.File]::ReadAllText($script:UsagePath)
        $Updated | Should -Match '(?m)^# Old Model\r?$'
        $Updated | Should -Match "'New Model' # Old Model"
        $Updated | Should -Match 'Final Model'
        $Updated | Should -Match 'New Model\r?\nFinal Model'
        [System.IO.File]::ReadAllText($script:RegistryPath) | Should -BeExactly $script:Registry
        [System.IO.File]::ReadAllText("$script:UsagePath.bak") | Should -BeExactly $Source
    }

    It 'does not treat a comment beside an unrelated literal as a model reference' {
        $Source = "`$Other = 'unrelated' # Old Model"
        [System.IO.File]::WriteAllText($script:UsagePath, $Source, $script:Utf8)

        & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null

        [System.IO.File]::ReadAllText($script:UsagePath) | Should -BeExactly $Source
        Test-Path -LiteralPath "$script:UsagePath.bak" | Should -BeFalse
    }

    It 'preserves UTF-8 content, BOM choice, and exact backup bytes: bom=<Bom>' -ForEach @(
        @{ Bom = $false }
        @{ Bom = $true }
    ) {
        $Usage = Join-Path $script:ScanRoot 'example.md'
        $Source = 'Old Model - caf' + [char]0x00E9
        [byte[]]$Bytes = $script:Utf8.GetBytes($Source)
        if ($Bom) { $Bytes = [byte[]](0xEF, 0xBB, 0xBF) + $Bytes }
        [System.IO.File]::WriteAllBytes($Usage, $Bytes)

        & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null

        [byte[]]$Expected = $script:Utf8.GetBytes($Source.Replace('Old Model', 'New Model'))
        if ($Bom) { $Expected = [byte[]](0xEF, 0xBB, 0xBF) + $Expected }
        [System.IO.File]::ReadAllBytes($Usage) | Should -Be $Expected
        [System.IO.File]::ReadAllBytes("$Usage.bak") | Should -Be $Bytes
    }

    It 'keeps an existing backup instead of overwriting it' {
        [System.IO.File]::WriteAllText($script:UsagePath, "`$Name = 'Old Model'", $script:Utf8)
        [System.IO.File]::WriteAllText("$script:UsagePath.bak", 'earlier backup', $script:Utf8)

        & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null

        [System.IO.File]::ReadAllText("$script:UsagePath.bak") | Should -BeExactly 'earlier backup'
        @(Get-ChildItem -LiteralPath $script:ScanRoot -Filter 'usage.ps1.*.bak').Count | Should -Be 1
    }

    It 'refuses to rewrite PowerShell that does not parse' {
        $Source = 'Write-Output "Old Model'
        [System.IO.File]::WriteAllText($script:UsagePath, $Source, $script:Utf8)

        { & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null } | Should -Throw '*does not parse*'

        [System.IO.File]::ReadAllText($script:UsagePath) | Should -BeExactly $Source
        Test-Path -LiteralPath "$script:UsagePath.bak" | Should -BeFalse
    }

    It 'keeps alias replacements as literal data: quote=<Quote>, doubleQuoted=<DoubleQuoted>' -ForEach @(
        @{ Quote = 0x27; DoubleQuoted = $false }
        @{ Quote = 0x2019; DoubleQuoted = $false }
        @{ Quote = 0x201D; DoubleQuoted = $false }
        @{ Quote = 0x27; DoubleQuoted = $true }
        @{ Quote = 0x2019; DoubleQuoted = $true }
        @{ Quote = 0x201D; DoubleQuoted = $true }
    ) {
        $Replacement = 'New Model' + [char]$Quote + '; throw ' + [char]$Quote + 'not code'
        $Registry = $script:Registry.Replace("'New Model'", ("'" + [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Replacement) + "'"))
        [System.IO.File]::WriteAllText($script:RegistryPath, $Registry, $script:Utf8)
        $Source = if ($DoubleQuoted) { '$Name = "Old Model"' } else { "`$Name = 'Old Model'" }
        [System.IO.File]::WriteAllText($script:UsagePath, $Source, $script:Utf8)

        & $script:ScannerPath -Path $script:ScanRoot -ApplyAliases | Out-Null

        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($script:UsagePath), [ref]$Tokens, [ref]$Errors)
        $Errors.Count | Should -Be 0
        $Ast.EndBlock.Statements.Count | Should -Be 1
        $Literal = $Ast.Find({ param ($Node) $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
        $Literal.Value | Should -BeExactly $Replacement
    }
}