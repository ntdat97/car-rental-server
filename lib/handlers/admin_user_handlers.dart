import 'dart:convert';
import 'dart:io';
import 'package:bcrypt/bcrypt.dart';
import 'package:shelf/shelf.dart';
import '../services/database_service.dart';
import '../services/service_locator.dart';
import '../auth/auth.dart';

class AdminUserHandlers {
  final DatabaseService dbService = serviceLocator.databaseService;

  /// GET /admin/users?search=&role=&status=
  Future<Response> getUsers(Request request) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final search = request.url.queryParameters['search'] ?? '';
      final role = request.url.queryParameters['role'] ?? '';
      final status = request.url.queryParameters['status'] ?? '';

      var query = 'SELECT User_ID, UserName, FirstName, LastName, Email, PhoneNumber, AvatarURL, DayOfBirth, Address, Role, IsBanned, BannedAt, BanReason, IsDeleted, DeletedAt, RegistrationDate FROM Users WHERE 1=1';
      final params = <Object>[];

      if (search.isNotEmpty) {
        query += ' AND (UserName LIKE ? OR FirstName LIKE ? OR LastName LIKE ? OR Email LIKE ?)';
        final searchPattern = '%$search%';
        params.addAll([searchPattern, searchPattern, searchPattern, searchPattern]);
      }

      if (role.isNotEmpty) {
        query += ' AND Role = ?';
        params.add(role);
      }

      if (status == 'active') {
        query += ' AND (IsBanned = 0 OR IsBanned IS NULL) AND (IsDeleted = 0 OR IsDeleted IS NULL)';
      } else if (status == 'banned') {
        query += ' AND IsBanned = 1 AND (IsDeleted = 0 OR IsDeleted IS NULL)';
      } else if (status == 'deleted') {
        query += ' AND IsDeleted = 1';
      }

      query += ' ORDER BY User_ID DESC';

      final results = await dbService.query(query, params);

      final users = results.map((row) => <String, dynamic>{
        'User_ID': row['User_ID'],
        'UserName': row['UserName'],
        'FirstName': row['FirstName'],
        'LastName': row['LastName'],
        'Email': row['Email'],
        'PhoneNumber': row['PhoneNumber'],
        'AvatarURL': row['AvatarURL'],
        'DayOfBirth': row['DayOfBirth']?.toString(),
        'Address': row['Address'],
        'Role': row['Role'],
        'IsBanned': (row['IsBanned'] ?? 0) == 1,
        'BannedAt': row['BannedAt']?.toString(),
        'BanReason': row['BanReason'],
        'IsDeleted': (row['IsDeleted'] ?? 0) == 1,
        'DeletedAt': row['DeletedAt']?.toString(),
        'RegistrationDate': row['RegistrationDate']?.toString(),
      }).toList();

      return Response.ok(
        json.encode({'success': true, 'data': users}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching users: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching users'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// GET /admin/users/<id>
  Future<Response> getUserById(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query(
        'SELECT User_ID, UserName, FirstName, LastName, Email, PhoneNumber, AvatarURL, DayOfBirth, Address, Role, IsBanned, BannedAt, BanReason, IsDeleted, DeletedAt, RegistrationDate FROM Users WHERE User_ID = ?',
        [userId],
      );

      if (results.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'User not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final row = results.first;
      final userData = {
        'User_ID': row['User_ID'],
        'UserName': row['UserName'],
        'FirstName': row['FirstName'],
        'LastName': row['LastName'],
        'Email': row['Email'],
        'PhoneNumber': row['PhoneNumber'],
        'AvatarURL': row['AvatarURL'],
        'DayOfBirth': row['DayOfBirth']?.toString(),
        'Address': row['Address'],
        'Role': row['Role'],
        'IsBanned': (row['IsBanned'] ?? 0) == 1,
        'BannedAt': row['BannedAt']?.toString(),
        'BanReason': row['BanReason'],
        'IsDeleted': (row['IsDeleted'] ?? 0) == 1,
        'DeletedAt': row['DeletedAt']?.toString(),
        'RegistrationDate': row['RegistrationDate']?.toString(),
      };

      return Response.ok(
        json.encode({'success': true, 'data': userData}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// POST /admin/users
  Future<Response> createUser(Request request) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;

      final username = body['username'] as String?;
      final password = body['password'] as String?;
      final firstName = body['firstName'] as String?;
      final lastName = body['lastName'] as String?;
      final email = body['email'] as String?;
      final phoneNumber = body['phoneNumber'] as String?;
      final role = body['role'] as String? ?? 'User';

      if (username == null || password == null || firstName == null || lastName == null || email == null) {
        return Response.badRequest(
          body: json.encode({'error': 'username, password, firstName, lastName, and email are required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Check username uniqueness
      final existing = await dbService.query(
        'SELECT 1 FROM Users WHERE UserName = ? LIMIT 1',
        [username],
      );
      if (existing.isNotEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'Username already taken'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Check email uniqueness
      final existingEmail = await dbService.query(
        'SELECT 1 FROM Users WHERE Email = ? LIMIT 1',
        [email],
      );
      if (existingEmail.isNotEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'Email already in use'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
      final now = DateTime.now().toUtc();

      final result = await dbService.query(
        'INSERT INTO Users (UserName, password_hash, FirstName, LastName, Email, PhoneNumber, Role, RegistrationDate) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [username, hashedPassword, firstName, lastName, email, phoneNumber, role, now],
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'User created', 'User_ID': result.insertId}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error creating user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error creating user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// PUT /admin/users/<id>
  Future<Response> updateUser(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;

      final updateFields = <String>[];
      final updateValues = <Object>[];

      final allowedFields = {
        'FirstName': 'FirstName',
        'LastName': 'LastName',
        'Email': 'Email',
        'PhoneNumber': 'PhoneNumber',
        'DayOfBirth': 'DayOfBirth',
        'Address': 'Address',
        'Role': 'Role',
      };

      for (final entry in allowedFields.entries) {
        if (body.containsKey(entry.key)) {
          final val = body[entry.key];
          if (val == null || (val is String && val.isEmpty)) {
            // Allow explicit null to clear nullable fields, skip empty strings
            if (const {'DayOfBirth', 'Address', 'PhoneNumber'}.contains(entry.key)) {
              updateFields.add('${entry.value} = NULL');
            }
          } else {
            updateFields.add('${entry.value} = ?');
            updateValues.add(val);
          }
        }
      }

      // Handle avatar upload if provided
      if (body.containsKey('Avatar') && body['Avatar'] != null) {
        final imageUrl = await serviceLocator.imageService
            .uploadImage(body['Avatar'] as String);
        if (imageUrl != null) {
          updateFields.add('AvatarURL = ?');
          updateValues.add(imageUrl);
        }
      }

      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'No valid fields to update'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      updateValues.add(userId);

      await dbService.query(
        'UPDATE Users SET ${updateFields.join(', ')} WHERE User_ID = ?',
        updateValues,
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'User updated'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error updating user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error updating user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// PUT /admin/users/<id>/ban
  Future<Response> banUser(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final reason = body['reason'] as String? ?? '';

      await dbService.query(
        'UPDATE Users SET IsBanned = 1, BannedAt = ?, BanReason = ? WHERE User_ID = ?',
        [DateTime.now().toUtc(), reason, userId],
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'User banned'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error banning user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error banning user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// PUT /admin/users/<id>/unban
  Future<Response> unbanUser(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      await dbService.query(
        'UPDATE Users SET IsBanned = 0, BannedAt = NULL, BanReason = NULL WHERE User_ID = ?',
        [userId],
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'User unbanned'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error unbanning user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error unbanning user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// DELETE /admin/users/<id> (soft delete)
  Future<Response> deleteUser(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      await dbService.query(
        'UPDATE Users SET IsDeleted = 1, DeletedAt = ? WHERE User_ID = ?',
        [DateTime.now().toUtc(), userId],
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'User deleted'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error deleting user: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error deleting user'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// PUT /admin/users/<id>/reset-password
  Future<Response> resetPassword(Request request, String id) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final userId = int.tryParse(id);
      if (userId == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final newPassword = body['newPassword'] as String?;

      if (newPassword == null || newPassword.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'newPassword is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final hashedPassword = BCrypt.hashpw(newPassword, BCrypt.gensalt());

      await dbService.query(
        'UPDATE Users SET password_hash = ? WHERE User_ID = ?',
        [hashedPassword, userId],
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'Password reset successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error resetting password: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error resetting password'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
