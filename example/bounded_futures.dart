import 'dart:async';
import 'dart:math';

Future<void> main() async {
  const taskCount = 12;
  var unboundedActive = 0;
  var unboundedPeak = 0;

  Future<void> unboundedTask(int id) async {
    unboundedActive += 1;
    unboundedPeak = max(unboundedPeak, unboundedActive);
    await Future<void>.delayed(Duration(milliseconds: 1 + id % 3));
    unboundedActive -= 1;
  }

  await Future.wait<void>(
    List<Future<void>>.generate(taskCount, unboundedTask),
  );
  final boundedPeak = await _runBounded(taskCount: taskCount, limit: 3);

  if (unboundedPeak != taskCount || boundedPeak != 3) {
    throw StateError(
      'Expected peaks $taskCount and 3, got $unboundedPeak and $boundedPeak',
    );
  }

  print('LAB_OK bounded_futures unbounded=$unboundedPeak bounded=$boundedPeak');
}

Future<int> _runBounded({required int taskCount, required int limit}) async {
  var nextTask = 0;
  var active = 0;
  var peak = 0;

  Future<void> worker() async {
    while (nextTask < taskCount) {
      final id = nextTask;
      nextTask += 1;
      active += 1;
      peak = max(peak, active);
      await Future<void>.delayed(Duration(milliseconds: 1 + id % 3));
      active -= 1;
    }
  }

  await Future.wait<void>(List<Future<void>>.generate(limit, (_) => worker()));
  return peak;
}
