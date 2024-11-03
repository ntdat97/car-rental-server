// import 'package:firebase_admin/firebase_admin.dart';

// class FCMService {
//   static final FCMService _instance = FCMService._internal();
//   factory FCMService() => _instance;
//   FCMService._internal();

//   static Future<FCMService> getInstance() async {
//     return _instance;
//   }

//   Future<void> sendNotification({
//     required String token,
//     required String title,
//     required String body,
//     Map<String, dynamic>? data,
//   }) async {
//     try {
//       final message = Message(
//         token: token,
//         notification: Notification(
//           title: title,
//           body: body,
//         ),
//         data: data,
//       );

//       final response = await FirebaseAdmin.instance.messaging.send(message);
//       print('Successfully sent message: $response');
//     } catch (e) {
//       print('Error sending FCM message: $e');
//       rethrow;
//     }
//   }
// } 