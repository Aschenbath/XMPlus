// Run with: dart tool/check_browser_captcha.dart
// Uses local HTTP requests only; never requests an SMS or contacts GeeTest.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lib/services/browser_captcha_session.dart';

const captchaId = '0123456789abcdef0123456789abcdef';
const validResult = {
  'captcha_id': captchaId,
  'lot_number': 'test-lot',
  'pass_token': 'test-pass',
  'gen_time': '1234567890',
  'captcha_output': 'test-output',
};

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<({int status, String body, HttpHeaders headers})> request(
  Uri uri, {
  String method = 'GET',
  String? origin,
  String? host,
  String? body,
  String contentType = 'application/json',
  bool declaredLength = true,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  client.findProxy = (_) => 'DIRECT';
  try {
    final req = await client.openUrl(method, uri);
    if (origin != null) req.headers.set('Origin', origin);
    if (host != null) req.headers.set('Host', host);
    if (body != null) {
      req.headers.set('Content-Type', contentType);
      final bytes = utf8.encode(body);
      if (declaredLength) req.contentLength = bytes.length;
      req.add(bytes);
    }
    final response = await req.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      headers: response.headers,
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> closed(Uri uri) async {
  try {
    await request(uri);
  } on SocketException {
    return;
  } on HttpException {
    return;
  }
  throw StateError('Listener remained open after the session ended');
}

Future<void> main() async {
  final session = await BrowserCaptchaSession.start(captchaId: captchaId);
  final uri = session.url;
  final callback = uri.resolve('result');
  try {
    check(uri.host == '127.0.0.1', 'Listener must bind loopback only');
    final page = await request(uri);
    check(page.status == 200, 'Challenge page was not served');
    check(
      page.headers.value('Cache-Control') == 'no-store',
      'Page was cacheable',
    );
    check(
      page.headers.value('Referrer-Policy') == 'no-referrer',
      'URL may leak',
    );
    check(
      page.headers
          .value('Content-Security-Policy')!
          .contains("frame-ancestors 'none'"),
      'Page must not be embedded',
    );
    check(page.body.contains('XMPlus 安全验证'), 'Page text missing');
    check(
      (await request(uri.replace(path: '/'))).status == 404,
      'Root URL must not disclose the callback',
    );
    check(
      (await request(uri, host: 'attacker.example')).status == 403,
      'Foreign Host was accepted',
    );
    check(
      (await request(uri.replace(query: 'extra=value'))).status == 403,
      'Unexpected query was accepted',
    );
    check(
      (await request(
            callback,
            method: 'OPTIONS',
            origin: 'https://example.com',
          )).status ==
          404,
      'Cross-origin preflight was accepted',
    );
    for (final origin in [null, 'null', 'https://example.com']) {
      final response = await request(
        callback,
        method: 'POST',
        origin: origin,
        body: jsonEncode(validResult),
      );
      check(response.status == 403, 'Foreign/missing Origin was accepted');
    }
    check(
      (await request(
            callback,
            method: 'POST',
            origin: uri.origin,
            contentType: 'text/plain',
            body: jsonEncode(validResult),
          )).status ==
          403,
      'Simple cross-origin content type was accepted',
    );
    for (final body in [
      '{',
      '[]',
      jsonEncode({...validResult, 'captcha_id': 'f' * 32}),
      jsonEncode({...validResult}..remove('pass_token')),
      jsonEncode({...validResult, 'extra': 'unexpected'}),
      jsonEncode({...validResult, 'pass_token': 123}),
      jsonEncode({...validResult, 'pass_token': ''}),
      jsonEncode({...validResult, 'pass_token': 'contains space'}),
      jsonEncode({...validResult, 'captcha_output': 'a' * 8193}),
    ]) {
      check(
        (await request(
              callback,
              method: 'POST',
              origin: uri.origin,
              body: body,
            )).status ==
            400,
        'Malformed challenge was accepted',
      );
    }
    for (final declaredLength in [true, false]) {
      check(
        (await request(
              callback,
              method: 'POST',
              origin: uri.origin,
              body: 'a' * (49 * 1024),
              declaredLength: declaredLength,
            )).status ==
            413,
        'Oversized request was accepted',
      );
    }
    check(
      (await request(
            callback,
            method: 'POST',
            origin: uri.origin,
            body: jsonEncode(validResult),
          )).status ==
          204,
      'Valid challenge was rejected after invalid requests',
    );
    final result = await session.result.timeout(const Duration(seconds: 2));
    check(
      jsonEncode(result) == jsonEncode(validResult),
      'Challenge changed in transit',
    );
    await session.close();
    await closed(uri);
    stdout.writeln(
      'PASS: browser page, request boundaries, result delivery, single use',
    );
  } finally {
    await session.close();
  }

  final cancelled = await BrowserCaptchaSession.start(captchaId: captchaId);
  final cancelUri = cancelled.url;
  await cancelled.close();
  await cancelled.close();
  check(await cancelled.result == null, 'Cancellation returned a challenge');
  await closed(cancelUri);
  stdout.writeln('PASS: cancellation and repeated disposal');

  final expired = await BrowserCaptchaSession.start(
    captchaId: captchaId,
    timeout: const Duration(milliseconds: 100),
  );
  final expireUri = expired.url;
  check(
    await expired.result.timeout(const Duration(seconds: 2)) == null,
    'Timeout returned a challenge',
  );
  await expired.close();
  await closed(expireUri);
  stdout.writeln('PASS: timeout closes the listener');

  final first = await BrowserCaptchaSession.start(captchaId: captchaId);
  final second = await BrowserCaptchaSession.start(captchaId: captchaId);
  try {
    check(
      first.url.path != second.url.path,
      'Sessions reused a callback secret',
    );
    check(
      (await request(
            second.url.replace(path: first.url.resolve('result').path),
            method: 'POST',
            origin: second.url.origin,
            body: jsonEncode(validResult),
          )).status ==
          404,
      'Old session URL was accepted by a new session',
    );
  } finally {
    await first.close();
    await second.close();
  }
  stdout.writeln('PASS: sessions are independent');

  final concurrent = await BrowserCaptchaSession.start(captchaId: captchaId);
  final concurrentUrl = concurrent.url;
  try {
    Future<bool> submit() async {
      try {
        return (await request(
              concurrentUrl.resolve('result'),
              method: 'POST',
              origin: concurrentUrl.origin,
              body: jsonEncode(validResult),
            )).status ==
            204;
      } on SocketException {
        return false;
      } on HttpException {
        return false;
      }
    }

    final accepted = await Future.wait([submit(), submit()]);
    check(
      accepted.where((value) => value).length == 1,
      'Duplicate callbacks succeeded',
    );
    check(
      await concurrent.result != null,
      'Concurrent callback lost its result',
    );
    await concurrent.close();
    await closed(concurrentUrl);
  } finally {
    await concurrent.close();
  }
  stdout.writeln('PASS: concurrent callbacks accept exactly one result');
}
