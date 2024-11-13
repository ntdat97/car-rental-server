import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dotenv/dotenv.dart';
import 'package:googleapis_auth/auth_io.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final env = DotEnv()..load();
  final String baseUrl = 'https://fcm.googleapis.com/v1/projects';
  late final String projectId;
  
  static Future<FCMService> getInstance() async {
    final instance = _instance;
    instance.projectId = instance.env['FIREBASE_PROJECT_ID'] ?? 
        (throw StateError('FIREBASE_PROJECT_ID not found in environment variables'));
    return instance;
  }

  Future<String> _getAccessToken() async {
    try {
      final credentialsPath = env['GOOGLE_APPLICATION_CREDENTIALS'] ?? 
          (throw StateError('GOOGLE_APPLICATION_CREDENTIALS not found in environment variables'));
      
      print('Loading credentials from: $credentialsPath');
      
      final credentialsFile = File(credentialsPath);
      if (!await credentialsFile.exists()) {
        throw FileSystemException('Credentials file not found', credentialsPath);
      }
      
      final credentialsJson = await credentialsFile.readAsString();
      final credentials = ServiceAccountCredentials.fromJson(
        json.decode(credentialsJson)
      );

      final client = await clientViaServiceAccount(
        credentials, 
        ['https://www.googleapis.com/auth/firebase.messaging']
      );
      
      final accessToken = await client.credentials.accessToken;
      return accessToken.data;
    } catch (e, stackTrace) {
      print('Error getting access token: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> sendNotification({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Validate token format
      if (token.isEmpty || token.startsWith('fak_')) {
        throw FormatException('Invalid FCM token format');
      }

      final accessToken = await _getAccessToken();
      
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      final request = {
        'message': {
          'token': token,
          'notification': {
            'title': title,
            'body': body,
          },
          if (data != null && data.isNotEmpty) 
            'data': data.map((key, value) => MapEntry(key, value.toString())),
        }
      };

      print('Sending FCM request: ${json.encode(request)}');

      final response = await http.post(
        Uri.parse('$baseUrl/$projectId/messages:send'),
        headers: headers,
        body: json.encode(request),
      );

      if (response.statusCode == 200) {
        print('Successfully sent FCM message: ${response.body}');
      } else {
        // Handle specific FCM errors
        final errorBody = json.decode(response.body);
        if (errorBody['error']?['details']?[0]?['errorCode'] == 'UNREGISTERED') {
          // Token is invalid, you might want to remove it from your database
          throw TokenUnregisteredException(token);
        }
        throw Exception('Failed to send FCM message: ${response.body}');
      }
    } catch (e) {
      print('Error sending FCM message: $e');
      rethrow;
    }
  }

  Future<void> sendMultipleNotifications({
    required List<String> tokens,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      int successCount = 0;
      List<String> failedTokens = [];

      for (String token in tokens) {
        try {
          await sendNotification(
            token: token,
            title: title,
            body: body,
            data: data,
          );
          successCount++;
        } catch (e) {
          print('Failed to send message to token $token: $e');
          failedTokens.add(token);
        }
      }

      print('Successfully sent messages to $successCount devices');
      if (failedTokens.isNotEmpty) {
        print('Failed to send messages to ${failedTokens.length} devices');
      }
    } catch (e) {
      print('Error sending multiple notifications: $e');
      rethrow;
    }
  }
}

// Custom exception for unregistered tokens
class TokenUnregisteredException implements Exception {
  final String token;
  TokenUnregisteredException(this.token);
  
  @override
  String toString() => 'FCM token is unregistered: $token';
} 