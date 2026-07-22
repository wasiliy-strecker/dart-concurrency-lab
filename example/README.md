# Executable labs

Each file is a small executable with an internal assertion. A lab prints
`LAB_OK` only when the observed behavior matches the documented concurrency
contract.

Run all labs through the tests:

```sh
dart test test/labs
```

Or run one directly:

```sh
dart run example/stream_backpressure.dart
```

The examples intentionally use only Dart SDK APIs. The production pipeline in
`lib/` applies the same ideas with explicit lifecycle and failure handling.
