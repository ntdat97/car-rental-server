import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import 'dart:io';
import '../auth/auth.dart';
import '../models/enums.dart';

class CarHandlers {
  final dbService = serviceLocator.databaseService;

  Future<Response> getAllCars(Request request) async {
    try {
      final params = request.url.queryParameters;
      final startDate = params['startDate'];
      final endDate = params['endDate'];

      // If no dates provided, use simple query
      if (startDate == null || endDate == null) {
        return await _getBasicCarList(params);
      }

      // Use complex query for date-based availability
      return await _getAvailableCarsForDates(startDate, endDate, params);
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

  // Simple query for basic listing
  Future<Response> _getBasicCarList(Map<String, String> params) async {
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

    return Response.ok(
      json.encode({
        'success': true,
        'data': results.map((row) => row.fields).toList()
      }),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
    );
  }

  // Complex query for date-based availability
  Future<Response> _getAvailableCarsForDates(
    String startDate, 
    String endDate, 
    Map<String, String> params
  ) async {
    var query = '''
      SELECT DISTINCT c.*, 
        CASE 
          WHEN crf.Car_ID IS NOT NULL THEN 'contract'
          ELSE 'admin'
        END as car_type,
        c.PricePerDay as price_per_day,
        GROUP_CONCAT(cp.CP_Link) as image_urls
      FROM cars c
      LEFT JOIN carrentalregistrationform crf ON c.Car_ID = crf.Car_ID
      LEFT JOIN carpictures cp ON c.Car_ID = cp.Car_ID
      WHERE 
        -- Car must be Available
        c.Status = 'Available'
        AND (
          -- Admin Cars (no contract)
          (crf.Car_ID IS NULL AND NOT EXISTS (
            SELECT 1 FROM serviceapplicationform saf
            WHERE saf.Car_ID = c.Car_ID
              AND saf.Status = 'Approved'
              AND (
                (saf.StartDate BETWEEN ? AND ?)
                OR (saf.EndDate BETWEEN ? AND ?)
                OR (? BETWEEN saf.StartDate AND saf.EndDate)
              )
          ))
          OR
          -- Contract Cars
          (crf.Car_ID IS NOT NULL 
           -- Check contract period
           AND ? BETWEEN crf.StartDateTime AND crf.EndDateTime
           AND ? BETWEEN crf.StartDateTime AND crf.EndDateTime
           AND crf.Status = 'Approved'
           -- Check no existing bookings
           AND NOT EXISTS (
            SELECT 1 FROM serviceapplicationform saf
            WHERE saf.Car_ID = c.Car_ID
              AND saf.Status = 'Approved'
              AND (
                (saf.StartDate BETWEEN ? AND ?)
                OR (saf.EndDate BETWEEN ? AND ?)
                OR (? BETWEEN saf.StartDate AND saf.EndDate)
              )
          ))
        )
    ''';

    final queryParams = <Object>[
      // Admin car booking check
      startDate, endDate, startDate, endDate, startDate,
      // Contract period check
      startDate, endDate,
      // Contract car booking check
      startDate, endDate, startDate, endDate, startDate
    ];

    // Add additional filters
    if (params.containsKey('manufacturer')) {
      query += ' AND c.Manufacturer = ?';
      queryParams.add(params['manufacturer']!);
    }
    if (params.containsKey('seats')) {
      query += ' AND c.Seat = ?';
      queryParams.add(int.parse(params['seats']!));
    }

    // Add GROUP BY for image concatenation
    query += ' GROUP BY c.Car_ID';

    final results = await dbService.query(query, queryParams);

    // Transform results to include parsed image URLs
    final transformedResults = results.map((row) {
      final fields = Map<String, dynamic>.from(row.fields);
      
      // Parse concatenated image URLs into a list
      if (fields['image_urls'] != null) {
        fields['image_urls'] = (fields['image_urls'] as String).split(',');
      } else {
        fields['image_urls'] = [];
      }

      return fields;
    }).toList();

    return Response.ok(
      json.encode({
        'success': true,
        'data': transformedResults
      }),
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
    );
  }

  Future<Response> addCar(Request request) async {
    try {
      // Check if user is Admin using isAdmin helper
      if (!isAdmin(request)) {
        return Response.forbidden(
          json.encode(
              {'success': false, 'error': 'Only administrators can add cars'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await json.decode(await request.readAsString())
          as Map<String, dynamic>;

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

      final missingFields = requiredFields
          .where((field) => !body.containsKey(field) || body[field] == null)
          .toList();

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
        final thumbnailUrl = await serviceLocator.imageService
            .uploadCompressedImage(base64Images[0],
                maxWidth: 400, // Adjust these values based on your needs
                maxHeight: 300,
                quality: 100);

        // Upload all original images for the CarPictures table
        final fullSizeImageUrls = await serviceLocator.imageService
            .uploadMultipleImages(base64Images);

        if (thumbnailUrl == null || fullSizeImageUrls.isEmpty) {
          throw Exception('Failed to upload images');
        }

        // Set initial status as Pending for partner cars, Available for admin cars
        final initialStatus = body['Contract_ID'] != null 
            ? CarStatus.Pending.name 
            : CarStatus.Available.name;

        // Insert into Cars table with the thumbnail
        final carResult = await dbService.query('''
          INSERT INTO Cars 
          (LicensePlate, Seat, Manufacturer, Model, Year, Transmission, FuelType, Status, PricePerDay, ImageURL)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
          body['LicensePlate'],
          body['Seat'],
          body['Manufacturer'],
          body['Model'],
          body['Year'],
          body['Transmission'],
          body['FuelType'],
          initialStatus,
          body['PricePerDay'],
          thumbnailUrl, // Use the compressed thumbnail
        ]);

        final carId = carResult.insertId;

        // Save image URLs to CarPictures table
        for (final imageUrl in fullSizeImageUrls) {
          await dbService.query('''
            INSERT INTO CarPictures (Car_ID, CP_Link)
            VALUES (?, ?)
            ''', [carId, imageUrl]);
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
        body: json.encode(
            {'success': false, 'error': 'Error adding car: ${e.toString()}'}),
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
          body:
              json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query('''
        SELECT CP_Link 
        FROM CarPictures 
        WHERE Car_ID = ?
        ORDER BY CP_ID
        ''', [id]);

      final imageUrls = results.map((row) => row['CP_Link'] as String).toList();

      return Response.ok(
        json.encode({
          'success': true,
          'data': {'carId': id, 'images': imageUrls, 'count': imageUrls.length}
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching car images: $e');
      return Response.internalServerError(
        body: json
            .encode({'success': false, 'error': 'Error fetching car images'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<Response> updateCarStatus(Request request) async {
    try {
      final params = request.url.queryParameters;
      final carId = int.parse(params['carId'] ?? '');
      final newStatus = params['status'];

      // Validate status
      if (!CarStatus.values.map((e) => e.name).contains(newStatus)) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Invalid status value'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      await dbService.query(
        'UPDATE Cars SET Status = ? WHERE Car_ID = ?',
        [newStatus, carId]
      );

      return Response.ok(
        json.encode({
          'success': true,
          'message': 'Car status updated successfully'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error updating car status: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Failed to update car status'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
