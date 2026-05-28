import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../state/user_state.dart';

class DioAdapter {
  late final Dio dio;
  late final BaseOptions options;
  DioAdapter() {
    BaseOptions options = BaseOptions(
      baseUrl: "${ApiPaths.baseUrl}:${ApiPaths.port}${ApiPaths.publicHead}",
      connectTimeout: const Duration(milliseconds: ApiPaths.connectTimeout),
      receiveTimeout: const Duration(milliseconds: ApiPaths.receiveTimeout),
      headers: {'Content-Type': 'application/json'},
    );
    this.options = options;
    dio = Dio(options);

    // 自动注入认证 Token
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = UserState.instance.token;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          debugPrint('[API] trigger ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[API] success ${response.requestOptions.method} '
            '${response.requestOptions.uri} status=${response.statusCode}',
          );
          return handler.next(response);
        },
        onError: (error, handler) {
          debugPrint(
            '[API] failure ${error.requestOptions.method} '
            '${error.requestOptions.uri} error=${error.message}',
          );
          return handler.next(error);
        },
      ),
    );
  }

  String _normalizePath(String path) {
    return path.startsWith('/') ? path.substring(1) : path;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return dio.get<T>(
      _normalizePath(path),
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return dio.post<T>(
      _normalizePath(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return dio.put<T>(
      _normalizePath(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return dio.delete<T>(
      _normalizePath(path),
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }
}
