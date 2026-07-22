import 'dart:async';

Future<void> main() async {
  final events = <String>[];

  events.add('sync:start');
  scheduleMicrotask(() => events.add('microtask'));
  unawaited(Future<void>(() => events.add('event:future')));
  Timer.run(() => events.add('event:timer'));
  events.add('sync:end');

  await Future<void>.delayed(const Duration(milliseconds: 10));

  const expected = <String>[
    'sync:start',
    'sync:end',
    'microtask',
    'event:future',
    'event:timer',
  ];
  if (!_sameValues(events, expected)) {
    throw StateError('Unexpected event order: $events');
  }

  print('LAB_OK event_loop ${events.join(' -> ')}');
}

bool _sameValues(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
