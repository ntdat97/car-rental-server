import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import '../models/enums.dart';

class PartnerHandlers {
  final dbService = serviceLocator.databaseService;
  Future<Response> updatePartnerRentalStatus(
      Request request, String applicationId) async {
    try {
      final body = await request.readAsString().then(json.decode);

      if (!body.containsKey('status')) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Status is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final newStatus = body['status'] as String;

      // Validate status
      if (!ServiceStatus.values.map((e) => e.name).contains(newStatus)) {
        return Response.badRequest(
          body:
              json.encode({'success': false, 'error': 'Invalid status value'}),
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
      FROM carrentalregistrationform r
      JOIN Users u ON r.User_ID = u.User_ID
      JOIN Cars c ON r.Car_ID = c.Car_ID
      WHERE r.CRRF_ID = ?
    ''', [applicationId]);

      if (rentalInfo.isEmpty) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Partner rental application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Update the status
      final result = await dbService.query(
          'UPDATE carrentalregistrationform SET Status = ? WHERE CRRF_ID = ?',
          [newStatus, applicationId]);

      if (result.affectedRows == 0) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Partner rental application not found'
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
            'SELECT FCM_Token FROM userfcmtokens WHERE User_ID = ?', [userId]);

        if (tokenResult.isNotEmpty) {
          final fcmToken = tokenResult.first['FCM_Token'];
          final carName = '${rental['Manufacturer']} ${rental['Model']}';

          // Prepare notification message based on status
          String title;
          String body;

          switch (newStatus) {
            case 'Approved':
              title = 'Partner Rental Approved';
              body =
                  'Your partner rental request for $carName has been approved!';
              break;
            case 'Rejected':
              title = 'Partner Rental Rejected';
              body =
                  'Your partner rental request for $carName has been rejected.';
              break;
            case 'Completed':
              title = 'Partner Rental Completed';
              body =
                  'Your partner rental for $carName has been marked as completed.';
              break;
            case 'Cancelled':
              title = 'Partner Rental Cancelled';
              body = 'Your partner rental for $carName has been cancelled.';
              break;
            default:
              title = 'Partner Rental Status Update';
              body =
                  'Your partner rental status for $carName has been updated to $newStatus.';
          }

          await serviceLocator.fcmService.sendNotification(
            token: fcmToken,
            title: title,
            body: body,
            data: {
              'type': 'partner_rental_status_update',
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
          'message': 'Partner rental status updated successfully'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error updating partner rental status: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Failed to update partner rental status'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  
  Future<Response> createCarPartnerRegistration(Request request) async {
    try {
      final userInfo = request.context['user'] as Map<String, dynamic>?;
      if (userInfo == null) {
        return Response.unauthorized(
          json.encode({
            'success': false,
            'error': 'User not authenticated'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;
      
      // Validate required fields
      final requiredFields = [
        'LicensePlate', 
        'Seat', 
        'Manufacturer', 
        'Model', 
        'Year', 
        'Transmission', 
        'FuelType', 
        'Status', 
        'PricePerDay',
        'Images',
        'StartDateTime',  // New field
        'EndDateTime'     // New field
      ];
      
      final missingFields = requiredFields.where((field) => !body.containsKey(field) || body[field] == null).toList();
      
      if (missingFields.isNotEmpty) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Missing required fields: ${missingFields.join(", ")}'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Validate dates
      final startDateTime = DateTime.tryParse(body['StartDateTime']);
      final endDateTime = DateTime.tryParse(body['EndDateTime']);
      
      if (startDateTime == null || endDateTime == null) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid date format. Use ISO 8601 format (e.g., "2024-03-20T10:00:00Z")'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      if (startDateTime.isBefore(DateTime.now())) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Start date cannot be in the past'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      if (endDateTime.isBefore(startDateTime)) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'End date must be after start date'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      await dbService.query('START TRANSACTION');

      try {
        final List<String> base64Images = List<String>.from(body['Images']);
        
        final thumbnailUrl = await serviceLocator.imageService.uploadCompressedImage(
          base64Images[0],
          maxWidth: 400,
          maxHeight: 300,
          quality: 100
        );

        final fullSizeImageUrls = await serviceLocator.imageService.uploadMultipleImages(base64Images);

        if (thumbnailUrl == null || fullSizeImageUrls.isEmpty) {
          throw Exception('Failed to upload images');
        }

        // Insert into Cars table
        final carResult = await dbService.query(
          '''
          INSERT INTO Cars 
          (LicensePlate, Seat, Manufacturer, Model, Year, Transmission, FuelType, Status, PricePerDay, ImageURL, Deposit, Odometer, InspectionDate, InspectionExpiry)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            body['LicensePlate'],
            body['Seat'],
            body['Manufacturer'],
            body['Model'],
            body['Year'],
            body['Transmission'],
            body['FuelType'],
            'Pending',
            body['PricePerDay'],
            thumbnailUrl,
            body['Deposit'] ?? 0,
            body['Odometer'] ?? 0,
            body['InspectionDate'],
            body['InspectionExpiry'],
          ]
        );

        final carId = carResult.insertId;

        // Save image URLs to CarPictures table
        for (final imageUrl in fullSizeImageUrls) {
          await dbService.query(
            '''
            INSERT INTO CarPictures (Car_ID, CP_Link)
            VALUES (?, ?)
            ''',
            [carId, imageUrl]
          );
        }

        // Calculate total amount based on number of days and price per day
        final days = endDateTime.difference(startDateTime).inDays + 1; // +1 to include both start and end days
        final totalAmount = days * (body['PricePerDay'] as num);

        // Create rental application
        final applicationResult = await dbService.query(
          '''
          INSERT INTO carrentalregistrationform 
          (StartDateTime, EndDateTime, Status, User_ID, Car_ID, TotalAmount)
          VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [
            startDateTime.toIso8601String(),
            endDateTime.toIso8601String(),
            ServiceStatus.Pending.name,
            userInfo['User_ID'],
            carId,
            totalAmount,
          ]
        );

        await dbService.query('COMMIT');

        return Response.ok(
          json.encode({
            'success': true,
            'message': 'Car rental request submitted successfully',
            'data': {
              'applicationId': applicationResult.insertId,
              'carId': carId,
              'startDateTime': startDateTime.toIso8601String(),
              'endDateTime': endDateTime.toIso8601String(),
              'status': 'Pending',
              'car': {
                'licensePlate': body['LicensePlate'],
                'seat': body['Seat'],
                'manufacturer': body['Manufacturer'],
                'model': body['Model'],
                'year': body['Year'],
                'transmission': body['Transmission'],
                'fuelType': body['FuelType'],
                'pricePerDay': body['PricePerDay'],
                'images': fullSizeImageUrls,
              }
            }
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );

      } catch (e) {
        await dbService.query('ROLLBACK');
        throw e;
      }

    } catch (e) {
      print('Error processing car rental request: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error processing car rental request: ${e.toString()}'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<Response> getAllPartnerApplications(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized(
        json.encode({
          'success': false,
          'error': 'User not authenticated'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }

    try {
      final params = request.url.queryParameters;
      final whereConditions = <String>[];
      final queryParams = <Object>[];

      // Non-admin users can only see their own partner applications
      final role = userInfo['Role'] as String? ?? 'User';
      if (role != 'Admin') {
        whereConditions.add('crf.User_ID = ?');
        queryParams.add(userInfo['User_ID'] as int);
      } else if (params.containsKey('userId')) {
        // Admin can filter by specific user
        whereConditions.add('crf.User_ID = ?');
        queryParams.add(int.parse(params['userId']!));
      }

      if (params.containsKey('status')) {
        whereConditions.add('crf.Status = ?');
        queryParams.add(params['status']!);
      }

      var query = '''
        SELECT 
          crf.CRRF_ID,
          crf.StartDateTime,
          crf.EndDateTime,
          crf.Status,
          crf.TotalAmount,
          u.UserName,
          u.FirstName,
          u.LastName,
          c.Model,
          c.Manufacturer,
          c.PricePerDay
        FROM carrentalregistrationform crf
        JOIN Users u ON crf.User_ID = u.User_ID
        JOIN Cars c ON crf.Car_ID = c.Car_ID
      ''';

      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }

      query += ' ORDER BY crf.CRRF_ID DESC';

      final results = await dbService.query(query, queryParams);

      final applications = results.map((row) {
        final application = Map<String, dynamic>.from(row.fields);
        
        application['StartDateTime'] = row['StartDateTime']?.toIso8601String();
        application['EndDateTime'] = row['EndDateTime']?.toIso8601String();
        
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
      print('Error fetching partner applications: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching partner applications'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<Response> getPartnerApplicationById(Request request, String id) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    
    if (userInfo == null) {
      return Response.unauthorized(
        json.encode({
          'success': false,
          'error': 'User not authenticated'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }

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

      final query = '''
        SELECT 
          crf.*,
          u.UserName,
          u.FirstName,
          u.LastName,
          u.PhoneNumber,
          u.Email,
          c.Model,
          c.Manufacturer,
          c.LicensePlate,
          c.Seat,
          c.Year,
          c.Transmission,
          c.FuelType,
          c.ImageURL,
          c.PricePerDay
        FROM carrentalregistrationform crf
        JOIN Users u ON crf.User_ID = u.User_ID
        JOIN Cars c ON crf.Car_ID = c.Car_ID
        WHERE crf.CRRF_ID = ?
      ''';

      final results = await dbService.query(query, [applicationId]);

      if (results.isEmpty) {
        return Response.notFound(
          json.encode({
            'success': false,
            'error': 'Application not found'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final row = results.first;
      final application = Map<String, dynamic>.from(row.fields);
      
      // Format the response
      final response = {
        'id': application['CRRF_ID'],
        'startDateTime': application['StartDateTime']?.toIso8601String(),
        'endDateTime': application['EndDateTime']?.toIso8601String(),
        'status': application['Status'],
        'totalAmount': application['TotalAmount'],
        'createdAt': application['CreatedAt']?.toIso8601String(),
        'user': {
          'id': application['User_ID'],
          'userName': application['UserName'],
          'firstName': application['FirstName'],
          'lastName': application['LastName'],
          'phoneNumber': application['PhoneNumber'],
          'email': application['Email']
        },
        'car': {
          'id': application['Car_ID'],
          'model': application['Model'],
          'manufacturer': application['Manufacturer'],
          'licensePlate': application['LicensePlate'],
          'seat': application['Seat'],
          'year': application['Year'],
          'transmission': application['Transmission'],
          'fuelType': application['FuelType'],
          'imageUrl': application['ImageURL'],
          'pricePerDay': application['PricePerDay']
        }
      };

      return Response.ok(
        json.encode({
          'success': true,
          'data': response
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching partner application: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching partner application'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

}
