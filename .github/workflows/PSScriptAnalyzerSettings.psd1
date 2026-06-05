@{
    # Severity levels to include in analysis
    Severity = @('Error', 'Warning')

    # Rules excluded after Stage 0 baseline review (2026-06-05)
    # Each exclusion is documented with rationale
    ExcludeRules = @(
        'PSAvoidGlobalVars',                           # By design: SAMISH uses $global: to share state across dot-sourced modules in a single PowerShell session
        'PSAvoidTrailingWhitespace',                   # Cosmetic only; has no runtime impact
        'PSAvoidUsingWriteHost',                       # Intentional use in installer UI, release scripts, and test output
        'PSAvoidUsingEmptyCatchBlock',                 # Mandated fail-forward pattern (Engineering Rule #3); empty catches wrap non-critical probes
        'PSUseApprovedVerbs',                          # Custom verbs (e.g. Log-Always) are established conventions in SAMISH
        'PSUseShouldProcessForStateChangingFunctions', # Not applicable to internal helper functions
        'PSUseSingularNouns'                           # Stylistic PowerShell convention; does not affect correctness
    )

    # Rules kept enabled (may reveal genuine issues):
    # - PSReviewUnusedParameter (61): Dead code detection
    # - PSUseDeclaredVarsMoreThanAssignments (32): Unused variable detection
    # - PSAvoidAssignmentToAutomaticVariable (24): Potential $_ assignment bugs
    # - PSAvoidUsingWMICmdlet (5): Deprecated Get-WmiObject usage
    # - PSPossibleIncorrectComparisonWithNull (5): $null comparison ordering
    # - PSAvoidUsingInvokeExpression (1): Security risk
    # - PSAvoidUsingPositionalParameters (1): Readability

    # NOTE: Third-party code (build-tools/node_modules/) must be excluded
    # via -ExcludePath on the command line, not in this settings file.
    # PSScriptAnalyzer settings files do not support path exclusions.
}
