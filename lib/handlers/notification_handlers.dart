import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';

class NotificationHandlers {
  final dbService = serviceLocator.databaseService;
  final fcmService = serviceLocator.fcmService;

  Future<Response> registerFCMToken(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      final userId = userInfo['User_ID'] as int;
      final body = await json.decode(await request.readAsString());
      final token = body['token'] as String?;

      if (token == null || token.isEmpty || token.startsWith('fak_')) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid FCM token format'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Delete all old tokens for this user, then insert the fresh one.
      // A user can only have one valid token at a time — when Firebase
      // refreshes the token the old entries become stale and cause
      // "FCM token is unregistered" errors.
      await dbService.query(
        'DELETE FROM userfcmtokens WHERE User_ID = ?',
        [userId],
      );
      await dbService.query(
        'INSERT INTO userfcmtokens (User_ID, FCM_Token) VALUES (?, ?)',
        [userId, token],
      );

      return Response.ok(
        json.encode({'success': true}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error registering FCM token: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Failed to register FCM token'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<void> sendUserNotification(
    int userId,
    String title,
    String body, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final results = await dbService.query(
        'SELECT FCM_Token FROM userfcmtokens WHERE User_ID = ?',
        [userId]
      );

      if (results.isNotEmpty) {
        final token = results.first['FCM_Token'] as String;
        await fcmService.sendNotification(
          token: token,
          title: title,
          body: body,
          data: data,
        );
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }
}
