import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8091';
  final host = 'http://127.0.0.1:$port';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    await p.stdout.first;
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

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });
}
