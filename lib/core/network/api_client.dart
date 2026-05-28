import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dio_adapter.dart';

class ApiClient {
  final DioAdapter _adapter = DioAdapter();

  Dio get dio => _adapter.dio;

  Future<Response> post(String path, {dynamic data}) async {
    debugPrint('[API] trigger ApiClient.post path=$path');
    final response = await _adapter.post(path, data: data);
    debugPrint(
      '[API] result ApiClient.post path=$path status=${response.statusCode}',
    );
    return response;
  }
}
