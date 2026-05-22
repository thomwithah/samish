# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.5] - Unreleased

### Added
- **Operating Mode Tests**: Added an "Operating Mode Tests" group box to the Setup UI, placed directly below the Install Mode and Operating Mode configuration boxes. Users can now manually trigger a Graceful stop, Classic stop, or Start against their selected device software or any app configured in Sleep and Hibernate Diagnostics, without waiting for sleep to trigger automatically. The box is greyed out (with tooltip visible) until SAMISH is installed, the device software is running, or automated apps are configured. Results are reported to the Status box with full detail.
- **Robust App Startup and Tracing**: Redesigned the application startup mechanism (`Invoke-AppStart`) to support a multi-stage launch fallback chain. It now aligns the working directory, executes local UWP aliases, uses shell execution, and falls back to protocol handlers. Added active process verification (polling the process list for up to 3 seconds) and detailed diagnostic trace reporting in the Status Box on success and failure.

## [1.0.4] - 2026-05-22

### Added
- **Per-App Wake Control**: Added a "Do not restart this app on wake" checkbox in the Sleep Diagnostics Operating Mode settings. This allows users to configure specific automated apps (like a web browser streaming media) to close before sleep but remain closed upon waking, without affecting critical mixer software.

## [1.0.3] - 2026-05-03

### Changed
- Stabilized SAMISH setup and engine operations.
- Resolved GUI initialization issues and character encoding artifacts.
- Optimized engine polling loop to maintain hotkey responsiveness.
- Improved adapter discovery system.
