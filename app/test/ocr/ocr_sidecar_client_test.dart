import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockcalc/ocr/ocr_models.dart';
import 'package:stockcalc/ocr/ocr_sidecar_client.dart';

void main() {
  test('recognize() returns text on 200', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/ocr');
      return http.Response(jsonEncode({'text': 'hello world', 'confidence': 0.97}), 200);
    });
    final client = OcrSidecarClient(httpClient: mock);

    final text = await client.recognize(Uint8List.fromList([1, 2, 3]));

    expect(text, 'hello world');
  });

  test('503 maps to engineUnavailable', () async {
    final mock = MockClient((request) async => http.Response('{}', 503));
    final client = OcrSidecarClient(httpClient: mock);

    await expectLater(
      client.recognize(Uint8List(0)),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.engineUnavailable)),
    );
  });

  test('non-200/503 maps to extractionFailed', () async {
    final mock = MockClient((request) async => http.Response('server error', 500));
    final client = OcrSidecarClient(httpClient: mock);

    await expectLater(
      client.recognize(Uint8List(0)),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.extractionFailed)),
    );
  });

  test('malformed JSON maps to extractionFailed', () async {
    final mock = MockClient((request) async => http.Response('not json', 200));
    final client = OcrSidecarClient(httpClient: mock);

    await expectLater(
      client.recognize(Uint8List(0)),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.extractionFailed)),
    );
  });

  test('missing text field maps to extractionFailed', () async {
    final mock = MockClient((request) async => http.Response(jsonEncode({'confidence': 0.5}), 200));
    final client = OcrSidecarClient(httpClient: mock);

    await expectLater(
      client.recognize(Uint8List(0)),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.extractionFailed)),
    );
  });

  test('connection failure maps to engineUnavailable', () async {
    final mock = MockClient((request) async => throw const SocketExceptionStub());
    final client = OcrSidecarClient(httpClient: mock);

    await expectLater(
      client.recognize(Uint8List(0)),
      throwsA(isA<OcrException>().having((e) => e.kind, 'kind', OcrErrorKind.engineUnavailable)),
    );
  });
}

/// Minimal stand-in so this test doesn't need dart:io's SocketException
/// import just to prove "any thrown Exception maps to engineUnavailable".
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
