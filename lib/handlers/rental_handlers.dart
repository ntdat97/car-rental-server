import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import '../models/enums.dart';

class RentalHandlers {
  final dbService = serviceLocator.databaseService;

  Future<Response> updateRentalStatus(Request request, String applicationId) async {
    try {
      final body = await request.readAsString().then(json.decode);
      
      if (!body.containsKey('status')) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Status is required'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final newStatus = body['status'] as String;
      
      // Validate status
      if (!ServiceStatus.values.map((e) => e.name).contains(newStatus)) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid status value'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Get user information and rental details
      final rentalInfo = await dbService.query('''
        SELECT 
          r.*,
          u.User_ID,
          c.Model,
          c.Manufacturer
        FROM serviceapplicationform r
        JOIN Users u ON r.User_ID = u.User_ID
        JOIN Cars c ON r.Car_ID = c.Car_ID
        WHERE r.SAF_ID = ?
      ''', [applicationId]);

      if (rentalInfo.isEmpty) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Rental application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Update the status
      final result = await dbService.query(
        'UPDATE serviceapplicationform SET Status = ? WHERE SAF_ID = ?',
        [newStatus, applicationId]
      );

      if (result.affectedRows == 0) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Rental application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Send notification to user
      try {
        final rental = rentalInfo.first;
        final userId = rental['User_ID'];
        
        // Get user's FCM token
        final tokenResult = await dbService.query(
          'SELECT FCM_Token FROM userfcmtokens WHERE User_ID = ?',
          [userId]
        );

        if (tokenResult.isNotEmpty) {
          final fcmToken = tokenResult.first['FCM_Token'];
          final carName = '${rental['Manufacturer']} ${rental['Model']}';
          
          // Prepare notification message based on status
          String title;
          String body;
          
          switch (newStatus) {
            case 'Approved':
              title = 'Rental Approved';
              body = 'Your rental request for $carName has been approved!';
              break;
            case 'Rejected':
              title = 'Rental Rejected';
              body = 'Your rental request for $carName has been rejected.';
              break;
            case 'Completed':
              title = 'Rental Completed';
              body = 'Your rental for $carName has been marked as completed.';
              break;
            case 'Cancelled':
              title = 'Rental Cancelled';
              body = 'Your rental for $carName has been cancelled.';
              break;
            default:
              title = 'Rental Status Update';
              body = 'Your rental status for $carName has been updated to $newStatus.';
          }

          await serviceLocator.fcmService.sendNotification(
            token: fcmToken,
            title: title,
            body: body,
            data: {
              'type': 'rental_status_update',
              'rental_id': applicationId,
              'status': newStatus,
              'car_name': carName,
            },
          );
        }
      } catch (e) {
        print('Error sending notification: $e');
        // Continue even if notification fails
      }

      return Response.ok(
        json.encode({
          'success': true,
          'message': 'Rental status updated successfully'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );

    } catch (e) {
      print('Error updating rental status: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Failed to update rental status'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
