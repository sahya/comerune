# Debug Info (Split Debug Symbols) Policy

## Overview

Release builds use `--obfuscate --split-debug-info=build/debug-info` to produce
obfuscated Dart code. The resulting debug symbol files are required to
de-obfuscate stack traces from crash reports.

## Storage

- CI uploads debug symbols as a GitHub Actions artifact named
  `debug-info-<version>` with a retention period of **180 days**.
- For production releases that require longer retention, download the artifact
  and archive it in the team's designated secure storage before expiry.

## Usage

To symbolicate an obfuscated stack trace:

```bash
flutter symbolize -i <obfuscated-stack-trace-file> -d build/debug-info/
```

## Retention Guidelines

| Release type | Minimum retention |
|---|---|
| Stable (vX.Y.Z) | 180 days (CI artifact) |
| Pre-release / beta | 90 days (CI artifact default) |

Extend retention manually if a version remains in active use beyond the CI
artifact expiry window.
