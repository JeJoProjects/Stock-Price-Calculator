import 'dart:convert';
import 'dart:typed_data';

import 'package:backend/yahoo_stream.dart';
import 'package:test/test.dart';

void main() {
  test('decodes a real pricing frame captured from the stream', () {
    // Captured from wss://streamer.finance.yahoo.com during regular hours.
    final t = PriceTick.decode('CgRBQVBMFYXLsUMY0KCSlbpoKgNOTVMwCDgBRSqPhD1ImIaKE2UAiGs+sAGkAtgBBPUCAIhrPv0CKo+EPQ==')!;
    expect(t.symbol, 'AAPL');
    expect(t.price, closeTo(355.59, 0.01));
    expect(t.session, MarketSession.regular);
    expect(t.changePercent, closeTo(0.0647, 0.0001));
    expect(t.dayVolume, 20005260);
    expect(t.exchange, 'NMS');
    expect(t.time.year, greaterThanOrEqualTo(2026));
  });

  test('garbage and symbol-less frames decode to null', () {
    expect(PriceTick.decode('not base64!!'), isNull);
    expect(PriceTick.decode(base64Encode([0x08, 0x01])), isNull); // only a varint field
  });

  test('protobuf reader handles every wire type it supports', () {
    final b = BytesBuilder()
      ..add([0x08, 0x96, 0x01]) // field 1 varint 150
      ..add([0x12, 0x02, 0x68, 0x69]) // field 2 "hi"
      ..add([0x1d]) // field 3 fixed32
      ..add((ByteData(4)..setFloat32(0, 1.5, Endian.little)).buffer.asUint8List())
      ..add([0x21]) // field 4 fixed64
      ..add((ByteData(8)..setFloat64(0, -2.25, Endian.little)).buffer.asUint8List());
    final f = decodeProtobuf(b.toBytes());
    expect(f[1], 150);
    expect(f[2], 'hi');
    expect(f[3], 1.5);
    expect(f[4], -2.25);
    expect(() => decodeProtobuf(Uint8List.fromList([0x12, 0x05, 0x61])), throwsFormatException);
  });
}
