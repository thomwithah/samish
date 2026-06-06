# Contributing to SAMISH

Thank you for your interest in contributing to SAMISH!

## Getting Started

1. Fork the repository and create a feature branch
2. Ensure PowerShell 5.1+ and [Pester v5](https://pester.dev/) are installed
3. Read `ARCHITECTURE.md` for codebase structure and conventions
4. Read `docs/Testing.md` for the test harness and mock guidelines

## Development Rules

All contributions must follow the rules in this section. PRs that violate these rules will be requested to fix them before merge.

### Code Standards

- **ASCII only** in `.ps1` and `.psm1` files. No em-dashes, en-dashes, or fancy arrows.
- **Try/catch fail-forward**: Wrap all external system calls in `try/catch`. The engine must never crash.
- **Explicit time units**: Comment all delays and timers with units (e.g., `# measured in ms`).
- **GDI resource cleanup**: Dispose all dynamically created `Font`, `Icon`, `Brush`, and `Pen` objects.
- **Module header blocks**: Every `.ps1`/`.psm1` must start with `#requires -Version 5.1` and a header block documenting purpose, inputs, outputs, and error handling.
- **Atomic config writes**: Use `Save-ContentAtomic` for all config file updates.
- **No hardcoded theme values**: All colors and fonts flow through `Theme-Extension.ps1`.

### Testing

- Run the full suite before submitting: `Invoke-Pester -Path Tests/ -Output Detailed`
- The lint baseline (0 errors, 21 warnings) must not regress
- New features should include test coverage where practical

### Commit Messages

Use clear, descriptive commit messages. Reference issue numbers where applicable.

## Reporting Issues

Use the [issue templates](https://github.com/ThomWithoutH/SAMISH/issues/new/choose) for bug reports and feature requests.

## Questions?

Open a [Discussion](https://github.com/ThomWithoutH/SAMISH/discussions) for questions about the codebase or development process.
