@{
    Severity = @('Warning', 'Error')
    ExcludeRules = @(
        # The New-* functions construct in-memory validation objects and do not
        # change external state, so ShouldProcess would be misleading.
        'PSUseShouldProcessForStateChangingFunctions',
        # These administrator-facing command scripts intentionally render
        # concise status output while keeping structured objects on the pipeline.
        'PSAvoidUsingWriteHost'
    )
}
