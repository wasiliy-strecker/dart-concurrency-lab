# Future, Stream, or isolate?

Start from the workload rather than the API name.

| Need | Prefer | Why |
| --- | --- | --- |
| one asynchronous result | `Future<T>` | one completion or one failure |
| many values over time | `Stream<T>` | subscription lifecycle, errors, pause and resume |
| concurrent I/O with a known resource limit | bounded Futures | I/O waits overlap without moving work to another isolate |
| CPU-heavy synchronous work | isolate | CPU work otherwise blocks the current isolate's event loop |
| tiny CPU task | current isolate | isolate startup and messages can cost more than the work |
| lifecycle-bound stop request | cooperative token | Dart Futures do not provide universal preemptive cancellation |
| catch unawaited asynchronous failures at a boundary | Zone | useful at process/test boundaries, not a substitute for awaiting |

## Common traps

### `Future.wait` is not a concurrency limit

Creating a list of Futures normally starts every operation before
`Future.wait` observes it. For thousands of file or network operations this can
exhaust sockets, descriptors, or memory. The bounded Futures lab measures the
peak directly.

### Futures do not parallelize CPU work

An `async` function still executes synchronous JSON parsing on its current
isolate. The event loop can interleave waits; it cannot run two synchronous
parsers in parallel on one isolate.

### Broadcast streams are not backpressure queues

A broadcast stream may keep producing when one listener is slow. The analyzer
uses a single-subscription source and stops requesting chunks at its batch
ceiling.

### More isolates can be slower

Messages copy most object graphs, scheduling has overhead, and parsing small
batches may be cheaper locally. Measure representative data and keep a
sequential correctness baseline.
