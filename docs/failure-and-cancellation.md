# Failure and cancellation semantics

## Data failures

Malformed UTF-8, oversized lines, invalid JSON, and schema violations are
expected input outcomes. They increment `invalidRecords`, receive stable codes,
and do not stop unrelated records. Only `maxErrors` detailed diagnostics are
retained, while the full invalid count remains exact.

With CLI `--strict`, the same report is written before exit code `1` is
returned.

## Infrastructure failures

An unexpected isolate exit is different from bad data. The dispatcher:

1. discards no completed aggregate;
2. requeues the worker's uncommitted batch once;
3. starts a replacement worker;
4. fails with `WorkerBatchException` if that batch fails again.

The coordinator merges by batch ID, so a late or duplicated response cannot
change counts.

## Cancellation

`AnalysisRun.cancel()` is cooperative and idempotent. It cancels demand from the
raw input stream, frames bytes already received, submits the final partial
batch, and waits for submitted batches. The resulting report has status
`cancelled` and is intentionally partial.

The CLI maps the first SIGINT to that graceful path. A second SIGINT calls the
process termination hook with exit code `130`.

## Deadlines

`AnalysisOptions.timeout` covers worker startup, input, parsing, and final
merging. Expiration follows the same cleanup path as cancellation but marks the
report `timed_out` and maps to CLI exit code `124`.

Cancellation is tested against a stream that never emits a byte. This protects
against implementations that only notice cancellation after the next source
event.

## Cleanup guarantee

Every completion path cancels the input iterator, closes progress, terminates
worker isolates, and cancels worker/signal subscriptions. The package does not
leave background workers alive after `AnalysisRun.done` completes.
