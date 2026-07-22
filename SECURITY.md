# Security policy

## Supported version

The latest `0.1.x` preview receives security fixes.

## Reporting

Please report a suspected vulnerability privately through GitHub's security
advisory flow rather than opening a public issue. Include a minimal sanitized
input and impact description; never attach private production logs.

## Data handling

The analyzer performs no network requests and stores no input. Reports contain
aggregate event types, timestamps, durations, line numbers, and safe error
codes. They do not echo source lines or payload fields. Consumers remain
responsible for deciding whether event type names themselves are sensitive.
