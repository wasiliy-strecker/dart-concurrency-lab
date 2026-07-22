# Dart Concurrency Lab

Executable Dart concurrency experiments with deterministic tests, benchmarks,
and a production-style streaming CLI.

This repository is under active construction. Version `0.1.0` will combine
focused event-loop, Future, Stream, isolate, and cancellation labs with a
bounded NDJSON analyzer that applies those techniques to one realistic tool.

Publication to pub.dev is intentionally disabled for the initial GitHub
release.

## Development

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

## License

MIT. See [LICENSE](LICENSE).
