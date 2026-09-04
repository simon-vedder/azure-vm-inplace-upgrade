@{
    Severity            = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules        = @(
        # Guest probe scripts are stored as here-strings and reviewed as text; the analyzer
        # cannot see them anyway. Nothing else in the module writes to the host.
        'PSAvoidUsingWriteHost'
        # "Facts" is the noun; Get-GuestFact would be wrong English for a bundle of values.
        'PSUseSingularNouns'
    )
    Rules               = @{
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space'; PipelineIndentation = 'IncreaseIndentationForFirstPipeline' }
        PSUseConsistentWhitespace  = @{ Enable = $true; CheckInnerBrace = $true; CheckOpenBrace = $true; CheckOpenParen = $true; CheckOperator = $true; CheckPipe = $true; CheckSeparator = $true; IgnoreAssignmentOperatorInsideHashTable = $true }
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true }
        PSPlaceCloseBrace          = @{ Enable = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true; NoEmptyLineBefore = $false }
        PSAvoidUsingCmdletAliases  = @{ Enable = $true }
    }
}
