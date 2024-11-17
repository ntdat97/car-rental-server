import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import '../models/rental_history_dto.dart';
import 'dart:io';
import '../models/enums.dart';
import '../auth/auth.dart';

class CarHandlers {
  final dbService = serviceLocator.databaseService;

  // Get all cars with filtering
  Future<Response> getAllCars(Request request) async {
    try {
      final params = request.url.queryParameters;
      final whereConditions = <String>[];
      final queryParams = <Object>[];

      if (params.containsKey('status')) {
        whereConditions.add('Status = ?');
        queryParams.add(params['status']!);
      }
      if (params.containsKey('manufacturer')) {
        whereConditions.add('Manufacturer = ?');
        queryParams.add(params['manufacturer']!);
      }
      if (params.containsKey('seats')) {
        whereConditions.add('Seat = ?');
        queryParams.add(int.parse(params['seats']!));
      }

      var query = 'SELECT * FROM cars';

      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }

      final results = await dbService.query(query, queryParams);

      final cars = results.map((row) => Map<String, dynamic>.from(row.fields)).toList();

      return Response.ok(
        json.encode({
          'success': true,
          'data': cars,
          'total': cars.length
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching cars: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching cars'
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
        whereConditions.add('Status = ?');
        queryParams.add(params['status']!);
      }

      // Add filters for specific user if provided
      if (params.containsKey('userId')) {
        whereConditions.add('User_ID = ?');
        queryParams.add(int.parse(params['userId']!));
      }

      var query = '''
        SELECT 
          saf.*,
          u.UserName,
          u.FirstName,
          u.LastName,
          c.Model,
          c.Manufacturer
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
          c.PricePerDay
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
      application['StartDate'] = row['StartDate']?.toIso8601String();
      application['EndDate'] = row['EndDate']?.toIso8601String();

      // Structure the response data
      final responseData = {
        'application': {
          'id': application['SAF_ID'],
          'startDate': application['StartDate'],
          'endDate': application['EndDate'],
          'status': application['Status'],
          'createdAt': application['CreatedAt']?.toIso8601String(),
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

  Future<Response> addCar(Request request) async {
    try {
      // Check if user is Admin using isAdmin helper
      if (!isAdmin(request)) {
        return Response.forbidden(
          json.encode({
            'success': false,
            'error': 'Only administrators can add cars'
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
        'Images'
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

      await dbService.query('START TRANSACTION');

      try {
        final List<String> base64Images = List<String>.from(body['Images']);
        
        // Create a thumbnail from the first image for the Cars table
        final thumbnailUrl = await serviceLocator.imageService.uploadCompressedImage(
          base64Images[0],
          maxWidth: 400,    // Adjust these values based on your needs
          maxHeight: 300,
          quality: 100
        );

        // Upload all original images for the CarPictures table
        final fullSizeImageUrls = await serviceLocator.imageService.uploadMultipleImages(base64Images);

        if (thumbnailUrl == null || fullSizeImageUrls.isEmpty) {
          throw Exception('Failed to upload images');
        }

        // Insert into Cars table with the thumbnail
        final carResult = await dbService.query(
          '''
          INSERT INTO Cars 
          (LicensePlate, Seat, Manufacturer, Model, Year, Transmission, FuelType, Status, PricePerDay, ImageURL)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            body['LicensePlate'],
            body['Seat'],
            body['Manufacturer'],
            body['Model'],
            body['Year'],
            body['Transmission'],
            body['FuelType'],
            body['Status'] ?? 'Available',
            body['PricePerDay'],
            thumbnailUrl,  // Use the compressed thumbnail
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

        // Commit the transaction
        await dbService.query('COMMIT');

        return Response.ok(
          json.encode({
            'success': true,
            'message': 'Car added successfully',
            'carId': carId,
            'imageUrls': fullSizeImageUrls,
            'car': {
              'id': carId,
              'licensePlate': body['LicensePlate'],
              'seat': body['Seat'],
              'manufacturer': body['Manufacturer'],
              'model': body['Model'],
              'year': body['Year'],
              'transmission': body['Transmission'],
              'fuelType': body['FuelType'],
              'status': body['Status'] ?? 'Available',
              'pricePerDay': body['PricePerDay'],
              'images': fullSizeImageUrls,
            }
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );

      } catch (e) {
        // Rollback in case of any error
        await dbService.query('ROLLBACK');
        throw e;
      }

    } catch (e) {
      print('Error adding car: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error adding car: ${e.toString()}'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Get all images for a specific car
  Future<Response> getCarImages(Request request, String carId) async {
    try {
      final id = int.tryParse(carId);
      if (id == null) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid car ID format'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query(
        '''
        SELECT CP_Link 
        FROM CarPictures 
        WHERE Car_ID = ?
        ORDER BY CP_ID
        ''',
        [id]
      );

      final imageUrls = results.map((row) => row['CP_Link'] as String).toList();

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'carId': id,
            'images': imageUrls,
            'count': imageUrls.length
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching car images: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error fetching car images'
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
          (LicensePlate, Seat, Manufacturer, Model, Year, Transmission, FuelType, Status, PricePerDay, ImageURL)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            body['LicensePlate'],
            body['Seat'],
            body['Manufacturer'],
            body['Model'],
            body['Year'],
            body['Transmission'],
            body['FuelType'],
            'Pending',  // Always set status as Pending for user submissions
            body['PricePerDay'],
            thumbnailUrl,
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

      if (params.containsKey('status')) {
        whereConditions.add('crf.Status = ?');
        queryParams.add(params['status']!);
      }

      if (params.containsKey('userId')) {
        whereConditions.add('crf.User_ID = ?');
        queryParams.add(int.parse(params['userId']!));
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
          c.Manufacturer
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
