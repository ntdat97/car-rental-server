import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/database_service.dart';
import '../services/service_locator.dart';

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

      // Convert row to Map
      final row = results.first;
      final userData = {
        'User_ID': row['User_ID'],
        'UserName': row['UserName'],
        'DayOfBirth': row['DayOfBirth']?.toString(),
        'Address': row['Address'],
        'PhoneNumber': row['PhoneNumber'],
        'FirstName': row['FirstName'],
        'LastName': row['LastName'],
        'AvatarURL': row['AvatarURL'],
      };

      return Response.ok(
        jsonEncode(userData),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching user data: $e');
      return Response.internalServerError(body: 'Error fetching user data');
    }
  }

  Future<Response> updateUserProfile(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;
      final username = userInfo['username'] as String;

      final updateFields = <String>[];
      final updateValues = <Object>[];

      // Handle avatar upload first if provided
      if (body['Avatar'] != null) {
        final imageUrl = await serviceLocator.imageService.uploadImage(body['Avatar'] as String);
        if (imageUrl != null) {
          updateFields.add('AvatarURL = ?');
          updateValues.add(imageUrl);
        }
      }

      // Map of allowed fields and their validation rules
      final allowedFields = {
        'FirstName': (String value) => value.length <= 45,
        'LastName': (String value) => value.length <= 45,
        'DayOfBirth': (String value) => DateTime.tryParse(value) != null,
        'Address': (String value) => value.length <= 100,
        'PhoneNumber': (String value) => value.length <= 10,
      };

      // Validate and add fields to update
      for (final entry in allowedFields.entries) {
        final field = entry.key;
        final validator = entry.value;
        
        if (body.containsKey(field)) {
          final value = body[field] as String?;
          if (value != null && validator(value)) {
            updateFields.add('$field = ?');
            updateValues.add(value);
          }
        }
      }

      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'No valid fields to update'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Add username to WHERE clause
      updateValues.add(username);

      await dbService.query(
        'UPDATE Users SET ${updateFields.join(', ')} WHERE UserName = ?',
        updateValues,
      );

      return Response.ok(
        json.encode({'message': 'Profile updated successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error updating user profile: $e');
      return Response.internalServerError(
        body: json.encode({'error': 'Error updating profile'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
