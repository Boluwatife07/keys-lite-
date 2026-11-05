import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Error returned by the Keys API. [code] drives screen states; [message] is
/// the user-facing copy chosen by the server.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.data = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> data;
  String? get field => data['field'] as String?;
  @override
  String toString() => 'ApiException($status, $code, $message)';
}

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client}) : _http = client ?? http.Client();
  final String baseUrl;
  final http.Client _http;
  String? token;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<Map<String, dynamic>> post(String path, [Object? body]) =>
      _send(() => _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  Future<Map<String, dynamic>> upload(String path, {required Uint8List bytes, required String filename, required String mime, Map<String, String>? query}) {
    return _send(() async {
      final req = http.MultipartRequest('POST', _uri(path, query));
      if (token != null) req.headers['authorization'] = 'Bearer $token';
      final parts = mime.split('/');
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType(parts[0], parts[1])));
      return http.Response.fromStream(await _http.send(req));
    });
  }

  String absolute(String url) => url.startsWith('http') ? url : '$baseUrl$url';

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() fn) async {
    http.Response res;
    try {
      res = await fn();
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'No connection. Check your internet and try again.');
    }
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final e = (body is Map && body['error'] is Map) ? Map<String, dynamic>.from(body['error']) : <String, dynamic>{};
      throw ApiException(res.statusCode, e['code'] as String? ?? 'ERROR', e['message'] as String? ?? 'Something went wrong. Please try again.', e);
    }
    return body is Map<String, dynamic> ? body : {'data': body};
  }
}

