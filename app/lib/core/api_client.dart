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

  Future<Map<String, dynamic>> postImages(
    String path,
    List<({List<int> bytes, String filename})> files,
  ) async {
    final form = FormData();
    for (final f in files) {
      form.files.add(
        MapEntry('images', MultipartFile.fromBytes(f.bytes, filename: f.filename)),
      );
    }
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: form,
      options: await _authed(),
    );
    return res.data ?? <String, dynamic>{};
  }
}
