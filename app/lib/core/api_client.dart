import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Every write goes through the API; the app never writes Firestore directly.
/// Attaches the current anonymous user's ID token to each request.
class ApiClient {
  ApiClient({required String baseUrl, FirebaseAuth? auth, Dio? dio})
      : _auth = auth ?? FirebaseAuth.instance,
        _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl));

  final FirebaseAuth _auth;
  final Dio _dio;

  Future<Options> _authed() async {
    final token = await _auth.currentUser?.getIdToken();
    return Options(headers: {if (token != null) 'Authorization': 'Bearer $token'});
  }

  Future<Map<String, dynamic>> postJson(String path, Object body) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> patchJson(String path, Object body) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      path,
      data: body,
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> postImages(
    String path,
    List<({List<int> bytes, String filename})> files, {
    String field = 'images',
  }) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(
        MapEntry(field, MultipartFile.fromBytes(f.bytes, filename: f.filename)),
      );
    }
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: form,
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }

  /// multipart with no file, because /orders/draft accepts either an image or
  /// a text field on the same endpoint.
  Future<Map<String, dynamic>> postForm(
    String path,
    Map<String, String> fields,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: FormData.fromMap(fields),
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }
}

/// Turns a thrown error into something a seller can act on.
///
/// Dio's own toString is "DioException [bad response]: ... status code of 400",
/// which tells a seller nothing. The API already sends a plain-English message
/// in `{ error: { message } }` — use it when it is there.
String describeApiError(Object error) {
  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['error'] is Map) {
      final message = (body['error'] as Map)['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Sorted could not reach the server. Check your connection and try again.';
    }
    return 'Something went wrong talking to the server. Please try again.';
  }
  if (error is ArgumentError) return error.message.toString();
  return 'Something went wrong. Please try again.';
}
