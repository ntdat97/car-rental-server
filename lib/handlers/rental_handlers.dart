import 'dart:convert';
import 'dart:io';
import 'package:car_rental_server/models/rental_history_dto.dart';
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

      // Block approving a Conflicted application
      if (newStatus == 'Approved') {
        final currentStatus = rentalInfo.first['Status'];
        if (currentStatus == 'Conflicted') {
          return Response.forbidden(
            json.encode({
              'success': false,
              'error': 'Cannot approve a conflicted application. This car is already booked for the requested period.'
            }),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }
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

      // Update car status based on rental status change
      {
        final rental = rentalInfo.first;
        final carId = rental['Car_ID'];

        if (newStatus == 'Approved') {
          // Mark car as Rented
          await dbService.query(
            "UPDATE Cars SET Status = 'Rented' WHERE Car_ID = ?",
            [carId]
          );
        } else if (newStatus == 'Completed' || newStatus == 'Cancelled') {
          // Only set back to Available if no other Approved rental exists for this car
          final otherApproved = await dbService.query('''
            SELECT SAF_ID FROM serviceapplicationform
            WHERE Car_ID = ? AND SAF_ID != ? AND Status = 'Approved'
          ''', [carId, applicationId]);

          if (otherApproved.isEmpty) {
            await dbService.query(
              "UPDATE Cars SET Status = 'Available' WHERE Car_ID = ?",
              [carId]
            );
          }
        }
      }

      // If approving, flag conflicting Pending applications as Conflicted
      if (newStatus == 'Approved') {
        final rental = rentalInfo.first;
        final carId = rental['Car_ID'];
        final startDate = rental['StartDate'].toString();
        final endDate = rental['EndDate'].toString();

        // Find conflicting Pending applications for the same car with overlapping dates
        final conflictingApps = await dbService.query('''
          SELECT saf.SAF_ID, saf.User_ID, c.Model, c.Manufacturer
          FROM serviceapplicationform saf
          JOIN Cars c ON saf.Car_ID = c.Car_ID
          WHERE saf.Car_ID = ?
            AND saf.SAF_ID != ?
            AND saf.Status = 'Pending'
            AND saf.StartDate <= ?
            AND saf.EndDate >= ?
        ''', [carId, applicationId, endDate, startDate]);

        if (conflictingApps.isNotEmpty) {
          // Update all conflicting applications to Conflicted
          final conflictIds = conflictingApps.map((row) => row['SAF_ID']).toList();
          for (final conflictId in conflictIds) {
            await dbService.query(
              'UPDATE serviceapplicationform SET Status = ? WHERE SAF_ID = ?',
              ['Conflicted', conflictId]
            );
          }

          // Send notification to each conflicted user
          for (final conflict in conflictingApps) {
            try {
              final conflictUserId = conflict['User_ID'];
              final carName = '${conflict['Manufacturer']} ${conflict['Model']}';
              final tokenResult = await dbService.query(
                'SELECT FCM_Token FROM userfcmtokens WHERE User_ID = ?',
                [conflictUserId]
              );
              if (tokenResult.isNotEmpty) {
                final fcmToken = tokenResult.first['FCM_Token'];
                await serviceLocator.fcmService.sendNotification(
                  token: fcmToken,
                  title: 'Rental Conflicted',
                  body: 'Your rental request for $carName has been conflicted because the car was approved for another customer during the same period.',
                  data: {
                    'type': 'rental_status_update',
                    'rental_id': conflict['SAF_ID'].toString(),
                    'status': 'Conflicted',
                    'car_name': carName,
                  },
                );
              }
            } catch (e) {
              print('Error sending conflict notification: $e');
            }
          }
        }
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
  
  // Get rental history
  Future<Response> getRentalHistory(Request request) async {
    try {
      final results = await dbService.query('SELECT * FROM RentalHistory');
      
      final List<RentalHistoryDto> rentalHistory = results.map((row) => 
        RentalHistoryDto(
          id: row['id'],
          carId: row['car_id'],
          userId: row['user_id'],
          rentalDate: row['rental_date'],
          returnDate: row['return_date'],
        )
      ).toList();

      return Response.ok(
        json.encode(rentalHistory.map((dto) => dto.toJson()).toList()),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching rental history: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching rental history'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Create rental registration
  Future<Response> createRentalRegistration(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;
      
      // Validate required fields
      if (!body.containsKey('StartDate') || 
          !body.containsKey('EndDate') || 
          !body.containsKey('Car_ID')) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Missing required fields: StartDate, EndDate, Car_ID'
          })
        );
      }

      // Get user ID from authenticated user context
      final userId = userInfo['User_ID'] as int;

      // Check if the car already has an Approved rental overlapping these dates
      final overlapping = await dbService.query('''
        SELECT SAF_ID FROM serviceapplicationform
        WHERE Car_ID = ? AND Status = 'Approved'
          AND StartDate <= ? AND EndDate >= ?
      ''', [body['Car_ID'], body['EndDate'], body['StartDate']]);

      if (overlapping.isNotEmpty) {
        return Response(409,
          body: json.encode({
            'success': false,
            'error': 'This car is already booked for the selected period'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Insert service application with default Pending status
      final result = await dbService.query(
        '''
        INSERT INTO serviceapplicationform 
        (StartDate, EndDate, Status, User_ID, Car_ID)
        VALUES (?, ?, ?, ?, ?)
        ''',
        [
          body['StartDate'],
          body['EndDate'],
          ServiceStatus.Pending.name,  // Using enum
          userId,
          body['Car_ID'],
        ]
      );

      return Response.ok(
        json.encode({
          'success': true,
          'message': 'Service application created successfully',
          'SAF_ID': result.insertId
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'}
      );
    } catch (e) {
      print('Error creating service application: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error creating service application'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'}
      );
    }
  }

  // Get all rental applications
  Future<Response> getAllRentalApplications(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      final params = request.url.queryParameters;
      final whereConditions = <String>[];
      final queryParams = <Object>[];

      // Add filters for status if provided
      if (params.containsKey('status')) {
        whereConditions.add('saf.Status = ?');
        queryParams.add(params['status']!);
      }

      // Add filters for specific user if provided
      if (params.containsKey('userId')) {
        whereConditions.add('saf.User_ID = ?');
        queryParams.add(int.parse(params['userId']!));
      }

      var query = '''
        SELECT 
          saf.*,
          u.UserName,
          u.FirstName,
          u.LastName,
          c.Model,
          c.Manufacturer,
          c.PricePerDay
        FROM serviceapplicationform saf
        JOIN Users u ON saf.User_ID = u.User_ID
        JOIN cars c ON saf.Car_ID = c.Car_ID
      ''';

      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }

      // Updated ordering to sort by SAF_ID instead of StartDate
      query += ' ORDER BY saf.SAF_ID DESC';

      final results = await dbService.query(query, queryParams);

      final applications = results.map((row) {
        final application = Map<String, dynamic>.from(row.fields);
        
        // Convert dates to ISO string format
        application['StartDate'] = row['StartDate']?.toIso8601String();
        application['EndDate'] = row['EndDate']?.toIso8601String();
        
        return application;
      }).toList();

      return Response.ok(
        json.encode({
          'success': true,
          'data': applications,
          'total': applications.length
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching rental applications: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching rental applications'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Get rental application by ID
  Future<Response> getRentalApplicationById(Request request, String id) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      // Validate ID format
      final applicationId = int.tryParse(id);
      if (applicationId == null) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid application ID format'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final query = '''
        SELECT 
          saf.*,
          u.UserName,
          u.FirstName,
          u.LastName,
          u.PhoneNumber,
          u.Email,
          u.AvatarURL,
          u.DayOfBirth,
          u.Address,
          c.Model,
          c.Manufacturer,
          c.LicensePlate,
          c.PricePerDay,
          c.ImageURL
        FROM serviceapplicationform saf
        JOIN Users u ON saf.User_ID = u.User_ID
        JOIN cars c ON saf.Car_ID = c.Car_ID
        WHERE saf.SAF_ID = ?
      ''';

      final results = await dbService.query(query, [applicationId]);

      if (results.isEmpty) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Rental application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final row = results.first;
      final application = Map<String, dynamic>.from(row.fields);
      
      // Convert dates to ISO string format
      final startDate = DateTime.parse(row['StartDate'].toString());
      final endDate = DateTime.parse(row['EndDate'].toString());
      
      // Calculate rental duration in days
      final duration = endDate.difference(startDate).inDays + 1; // Including both start and end days
      
      // Calculate total amount
      final pricePerDay = (row['PricePerDay'] as num).toDouble();
      final totalAmount = pricePerDay * duration;

      // Structure the response data
      final responseData = {
        'application': {
          'id': application['SAF_ID'],
          'startDate': startDate.toIso8601String(),
          'endDate': endDate.toIso8601String(),
          'status': application['Status'],
          'createdAt': application['CreatedAt']?.toIso8601String(),
          'duration': duration,
          'totalAmount': totalAmount,
        },
        'user': {
          'id': application['User_ID'],
          'userName': application['UserName'],
          'firstName': application['FirstName'],
          'lastName': application['LastName'],
          'phoneNumber': application['PhoneNumber'],
          'email': application['Email'],
          'avatarUrl': application['AvatarURL'],
          'dateOfBirth': application['DayOfBirth']?.toIso8601String(),
          'address': application['Address'],
        },
        'car': {
          'id': application['Car_ID'],
          'model': application['Model'],
          'manufacturer': application['Manufacturer'],
          'licensePlate': application['LicensePlate'],
          'pricePerDay': application['PricePerDay'],
        }
      };

      return Response.ok(
        json.encode({
          'success': true,
          'data': responseData,
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching rental application: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching rental application'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Get conflicting rental applications for a given application
  Future<Response> getConflicts(Request request, String id) async {
    try {
      final applicationId = int.tryParse(id);
      if (applicationId == null) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid application ID format'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Get the current application's car and date range
      final currentApp = await dbService.query('''
        SELECT Car_ID, StartDate, EndDate, Status
        FROM serviceapplicationform
        WHERE SAF_ID = ?
      ''', [applicationId]);

      if (currentApp.isEmpty) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final app = currentApp.first;
      final carId = app['Car_ID'];
      final startDate = app['StartDate'].toString();
      final endDate = app['EndDate'].toString();

      // Find overlapping applications (Pending or Approved) for the same car
      final conflicts = await dbService.query('''
        SELECT 
          saf.SAF_ID,
          saf.StartDate,
          saf.EndDate,
          saf.Status,
          u.FirstName,
          u.LastName,
          u.UserName
        FROM serviceapplicationform saf
        JOIN Users u ON saf.User_ID = u.User_ID
        WHERE saf.Car_ID = ?
          AND saf.SAF_ID != ?
          AND saf.Status IN ('Pending', 'Approved')
          AND saf.StartDate <= ?
          AND saf.EndDate >= ?
        ORDER BY saf.SAF_ID DESC
      ''', [carId, applicationId, endDate, startDate]);

      final conflictList = conflicts.map((row) {
        return {
          'SAF_ID': row['SAF_ID'],
          'StartDate': row['StartDate']?.toIso8601String(),
          'EndDate': row['EndDate']?.toIso8601String(),
          'Status': row['Status'],
          'FirstName': row['FirstName'],
          'LastName': row['LastName'],
          'UserName': row['UserName'],
        };
      }).toList();

      return Response.ok(
        json.encode({
          'success': true,
          'data': conflictList,
          'total': conflictList.length,
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching conflicts: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching conflicts'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
