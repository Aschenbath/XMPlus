// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A short-lived loopback bridge for the system browser. Only the five GeeTest
/// fields cross this bridge; phone numbers, SMS codes and login tokens do not.
class BrowserCaptchaSession {
  BrowserCaptchaSession._(this._server, this.captchaId, this._secret);

  static const _fields = [
    'captcha_id',
    'lot_number',
    'pass_token',
    'gen_time',
    'captcha_output',
  ];
  static const _bodyLimit = 48 * 1024;
  final HttpServer _server;
  final String captchaId, _secret;
  final _result = Completer<Map<String, dynamic>?>();
  Timer? _timer;
  Future<void>? _closing;
  bool _submitted = false;

  Uri get url => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: _server.port,
    path: '/$_secret/',
  );

  Future<Map<String, dynamic>?> get result => _result.future;

  static Future<BrowserCaptchaSession> start({
    required String captchaId,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(captchaId) ||
        timeout <= Duration.zero) {
      throw ArgumentError('Invalid captcha session');
    }
    final random = Random.secure();
    final secret = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final session = BrowserCaptchaSession._(server, captchaId, secret);
    server.listen(
      (request) => unawaited(session._handle(request)),
      onError: (Object _) => unawaited(session.close()),
      onDone: () => unawaited(session.close()),
    );
    session._timer = Timer(timeout, () => unawaited(session.close()));
    return session;
  }

  /// Cancelling/disposing the dialog invalidates the URL and pending callback.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _timer?.cancel();
    if (!_result.isCompleted) _result.complete(null);
    await _server.close(force: true);
  }

  Future<void> _respond(HttpRequest request, int status, [String? body]) async {
    request.response.statusCode = status;
    if (body != null) request.response.write(body);
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final response = request.response;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.headers.set('Referrer-Policy', 'no-referrer');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('X-Frame-Options', 'DENY');
      if (_result.isCompleted ||
          _submitted ||
          request.connectionInfo?.remoteAddress.isLoopback != true ||
          request.headers.value(HttpHeaders.hostHeader) != url.authority ||
          request.uri.hasQuery) {
        await _respond(request, HttpStatus.forbidden);
        return;
      }
      if (request.method == 'GET' && request.uri.path == url.path) {
        response.headers.contentType = ContentType.html;
        response.headers.set(
          'Content-Security-Policy',
          "default-src 'none'; "
              "script-src 'nonce-$_secret' https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; "
              "connect-src 'self' https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; "
              "img-src data: blob: https://*.geetest.com https://*.geevisit.com https://*.gsensebot.com; "
              "style-src 'unsafe-inline' https://*.geetest.com; font-src data: https://*.geetest.com; "
              "frame-src 'none'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'; form-action 'none'",
        );
        await _respond(request, HttpStatus.ok, _html());
        return;
      }
      if (request.method != 'POST' || request.uri.path != '${url.path}result') {
        await _respond(request, HttpStatus.notFound);
        return;
      }
      // A JSON POST from this exact origin is required. No CORS/preflight
      // support: another website cannot submit a challenge to this listener.
      if (request.headers.value('Origin') != url.origin ||
          request.headers.contentType?.mimeType != 'application/json') {
        await _respond(request, HttpStatus.forbidden);
        return;
      }
      if (request.contentLength > _bodyLimit) {
        await _respond(request, HttpStatus.requestEntityTooLarge);
        return;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        if (bytes.length + chunk.length > _bodyLimit) {
          await _respond(request, HttpStatus.requestEntityTooLarge);
          return;
        }
        bytes.add(chunk);
      }
      final raw = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (raw is! Map ||
          raw.length != _fields.length ||
          raw['captcha_id'] != captchaId ||
          _fields.any(
            (key) =>
                raw[key] is! String ||
                !RegExp(r'^[\x21-\x7e]{1,8192}$').hasMatch(raw[key] as String),
          )) {
        await _respond(request, HttpStatus.badRequest);
        return;
      }
      // An in-flight request may finish after cancellation or another tab.
      if (_result.isCompleted || _submitted) {
        await _respond(request, HttpStatus.gone);
        return;
      }
      final result = {for (final key in _fields) key: raw[key]};
      // Claim this session synchronously before flushing the response so that
      // two simultaneous browser callbacks cannot both be accepted.
      _submitted = true;
      _timer?.cancel();
      response.statusCode = HttpStatus.noContent;
      try {
        await response.close();
        if (!_result.isCompleted) _result.complete(result);
      } finally {
        await close();
      }
    } catch (_) {
      // Never include challenge fields, URLs or transport errors in logs.
      try {
        await _respond(request, HttpStatus.badRequest);
      } catch (_) {
        /* The browser disconnected or the session was cancelled. */
      }
    }
  }

  String _html() =>
      '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>XMPlus 安全验证</title>
<style>
body{font:16px/1.6 system-ui,sans-serif;color:#16302d;background:#f3faf8;margin:0;padding:48px 24px}
main{max-width:520px;margin:auto}h1{font-size:24px}button{font:inherit;padding:10px 20px;border:0;border-radius:20px;color:white;background:#00695c;cursor:pointer}
</style></head><body><main><h1>XMPlus 安全验证</h1>
<p id="status" role="status">正在加载安全验证…</p>
<button id="verify" hidden>开始验证</button>
<p>验证完成后，请回到 XMPlus 继续短信登录。此页面无需输入手机号或验证码。</p>
</main><script nonce="$_secret">
(() => {
  const status=document.getElementById('status'),button=document.getElementById('verify');
  let submitted=false;
  const fail=()=>{status.textContent='安全验证加载失败，请回到 XMPlus 关闭后重试。';};
  const script=document.createElement('script');
  script.src='https://static.geetest.com/v4/gt4.js';
  script.onerror=fail;
  script.onload=()=>{
    if(typeof initGeetest4!=='function'){fail();return;}
    initGeetest4({captchaId:${jsonEncode(captchaId)},product:'bind',language:'zho',https:true,onError:fail,offlineCb:fail},captcha=>{
      captcha.onReady(()=>{
        status.textContent='请完成安全验证';button.hidden=false;
        button.onclick=()=>captcha.showCaptcha();captcha.showCaptcha();
      }).onSuccess(async()=>{
        if(submitted)return;
        const value=captcha.getValidate();if(!value){fail();return;}
        submitted=true;button.hidden=true;
        const result={};
        ['captcha_id','lot_number','pass_token','gen_time','captcha_output'].forEach(k=>result[k]=value[k]);
        try{
          const response=await fetch('result',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(result),credentials:'omit'});
          if(!response.ok)throw new Error();
          status.textContent='验证完成，请回到 XMPlus 继续登录。可以关闭此页面。';
          captcha.destroy();
        }catch(_){status.textContent='无法返回 XMPlus，验证可能已过期。请回到应用关闭后重试。';}
      }).onError(fail);
    });
  };
  document.head.appendChild(script);
})();
</script></body></html>''';
}
