# Contributing

Contributions should preserve bounded resource use, deterministic JSON, and the
documented failure contract.

## Setup

```sh
dart pub get
make check
make coverage
```

Behavior changes need a focused test. Concurrency tests should assert an
invariant—such as a pressure ceiling, cleanup, or equivalent report—rather than
depending on a fragile wall-clock ordering. Benchmarks must not become CI speed
thresholds.

Run `dart format .` before submitting changes. Pull requests should explain the
failure or workload being addressed, verification commands, and any public API
or exit-code impact.
