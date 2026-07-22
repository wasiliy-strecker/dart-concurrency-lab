import 'dart:isolate';
import 'dart:typed_data';

Future<void> main() async {
  final bytes = Uint8List.fromList(
    List<int>.generate(10000, (int index) => index % 251),
  );
  final transfer = TransferableTypedData.fromList(<Uint8List>[bytes]);

  final checksum = await Isolate.run<int>(() => _checksum(transfer));
  final expected = bytes.fold<int>(0, (int sum, int byte) => sum + byte);

  if (checksum != expected) {
    throw StateError('Expected checksum $expected, got $checksum');
  }

  print('LAB_OK isolate_transfer bytes=${bytes.length} checksum=$checksum');
}

int _checksum(TransferableTypedData transfer) => transfer
    .materialize()
    .asUint8List()
    .fold<int>(0, (int sum, int byte) => sum + byte);
