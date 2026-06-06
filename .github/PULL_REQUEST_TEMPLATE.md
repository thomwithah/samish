## Summary

Brief description of the change and why it was made.

## Changes

- [ ] List of files modified and what changed in each

## Testing

- [ ] `Invoke-Pester -Path Tests/ -Output Detailed` passes (all tests green)
- [ ] Lint baseline maintained (0 errors, no new warnings)
- [ ] Manually tested the affected feature (if applicable)

## Checklist

- [ ] ASCII-only in `.ps1`/`.psm1` source files
- [ ] All external calls wrapped in `try/catch` (fail-forward)
- [ ] Time units documented on delays and timers
- [ ] No hardcoded theme values (colors/fonts flow through Theme-Extension.ps1)
- [ ] Module header blocks present on new files
