@{
    ExcludeRules = @(
        # The console output of an interactive installer is its product. Write-Output would put the
        # progress narration on the success stream, where it would be captured by anyone assigning
        # the script's result to a variable.
        'PSAvoidUsingWriteHost',

        # This is a top-level installer script, not a reusable module. Rather than exposing -WhatIf
        # on internal helpers, it backs up every file it overwrites to a timestamped folder.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
