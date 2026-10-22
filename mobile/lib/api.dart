import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CareFlowApi {
  CareFlowApi(this.session);

  final CareFlowSession session;

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = Uri.parse(session.baseUrl);
    return root.replace(
      path: '${root.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      _request('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _request('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _request('PATCH', path, body: body);

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.openUrl(method, _uri(path, query));
      session.headers.forEach(request.headers.set);
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      final text = await response.transform(utf8.decoder).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode >= 400) {
        throw ApiException(
          _errorMessage(decoded, response.reasonPhrase),
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on SocketException catch (error) {
      throw ApiException(
        'Cannot reach CareFlow at ${session.baseUrl}. Check the server and base URL. '
        '(${error.osError?.message ?? 'connection failed'})',
      );
    } on TimeoutException {
      throw ApiException('The CareFlow server did not respond in time.');
    } on FormatException {
      throw ApiException('The server returned an unreadable response.');
    } finally {
      client.close(force: true);
    }
  }

  String _errorMessage(dynamic decoded, String? fallback) {
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is Map && detail['message'] != null) {
        return detail['message'].toString();
      }
      if (detail != null) return detail.toString();
    }
    return fallback ?? 'Request failed';
  }
}
