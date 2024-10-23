import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/database_service.dart';  // Adjust import path as needed
import '../services/service_locator.dart';  // If you're using a service locator

class UserHandlers {
  final DatabaseService dbService = serviceLocator.databaseService;

  Future<Response> getCurrentUser(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    final username = userInfo['username'] as String;

    try {
      final results = await dbService.query(
        'SELECT * FROM Users WHERE username = ?',
        [username]
      );

      if (results.isEmpty) {
        return Response.notFound('User not found');
      }

      final userData = results.first;

      // Convert any non-JSON-serializable types (like DateTime) to strings
      final jsonSafeUserData = Map<String, dynamic>.from(userData as Map);
      jsonSafeUserData['created_at'] = userData['created_at'].toString();

      return Response.ok(
        jsonEncode(jsonSafeUserData),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching user data: $e');
      return Response.internalServerError(body: 'Error fetching user data');
    }
  }
}
