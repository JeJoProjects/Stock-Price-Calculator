import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  // Port 0 = any free port (8091 is the OCR sidecar's, often in use); the
  // server prints the one it got.
  late String port;
  late String host;
  late Process p;

  setUp(() async {
    p = await Process.start(
      Platform.resolvedExecutable, // the running dart.exe (a bare 'dart' may be a .bat Process.start can't run)
      ['run', 'bin/server.dart'],
      environment: {'PORT': '0'},
    );
    p.stderr.drain<void>();
    final line = await p.stdout.transform(utf8.decoder).first;
    port = RegExp(r'port (\d+)').firstMatch(line)!.group(1)!;
    host = 'http://127.0.0.1:$port';
  });

  tearDown(() => p.kill());

  test('Health', () async {
    final response = await get(Uri.parse('$host/health'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'status': 'ok'});
  });

  test('Finviz screener endpoint responds immediately, before the first poll completes', () async {
    final response = await get(Uri.parse('$host/screener/finviz'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['rows'], isEmpty);
  });

  test('Yahoo screener endpoint responds immediately, before the first poll completes', () async {
    final response = await get(Uri.parse('$host/screener/yahoo'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['rows'], isEmpty);
  });

  test('Combined screener endpoint responds immediately with an empty intersection', () async {
    final response = await get(Uri.parse('$host/screener/combined'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['rows'], isEmpty);
  });

  test('Scanner snapshot responds immediately', () async {
    final response = await get(Uri.parse('$host/scanner'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['type'], 'snapshot');
    expect(body['rows'], isA<List>());
  });

  test('Live socket pushes a snapshot on connect', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/live');
    final first = jsonDecode(await ws.first as String) as Map<String, dynamic>;
    expect(first['type'], 'snapshot');
    expect(first['stream'], isA<Map>());
    await ws.close();
  });

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });
}
