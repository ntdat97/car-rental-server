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
}
