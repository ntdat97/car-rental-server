import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import 'dart:io';
import '../auth/auth.dart';
import '../models/enums.dart';

class CarHandlers {
  final dbService = serviceLocator.databaseService;

  // Convert MySQL row fields to JSON-encodable map (handles DateTime, Blob, etc.)
  Map<String, dynamic> _sanitizeRow(Map<String, dynamic> row) {
    return row.map((key, value) {
      if (value is DateTime) {
        return MapEntry(key, value.toIso8601String().split('T')[0]); // date only
      }
      return MapEntry(key, value);
    });
  }

  // Get all cars with filtering
  Future<Response> getAllCars(Request request) async {
    try {
      final params = request.url.queryParameters;
      final whereConditions = <String>[];
      final queryParams = <Object>[];

      if (params.containsKey('status')) {
        whereConditions.add('c.Status = ?');
        queryParams.add(params['status']!);
      } else {
        // By default, exclude non-available cars (e.g. Flutter app browsing)
        // Admin web explicitly passes status or includeAll to see all
        if (params.containsKey('startDate')) {
          // When filtering by date, only show Available cars
          whereConditions.add("c.Status = 'Available'");
        } else if (!params.containsKey('includeAll')) {
          whereConditions.add("c.Status NOT IN ('Maintenance', 'Pending', 'Expired', 'Unavailable', 'Rented')");
        }
      }
      if (params.containsKey('manufacturer')) {
        whereConditions.add('c.Manufacturer = ?');
        queryParams.add(params['manufacturer']!);
      }
      if (params.containsKey('seats')) {
        whereConditions.add('c.Seat = ?');
        queryParams.add(int.parse(params['seats']!));
      }

      // Date-based availability: exclude cars that have an Approved rental overlapping the requested period
      // and ensure contract cars have their contract covering the requested period
      final hasDateFilter = params.containsKey('startDate') && params.containsKey('endDate');

      var query = 'SELECT c.* FROM cars c';

      if (hasDateFilter) {
        query += '''
          LEFT JOIN serviceapplicationform saf
            ON saf.Car_ID = c.Car_ID
            AND saf.Status = 'Approved'
            AND saf.StartDate <= ?
            AND saf.EndDate >= ?
          LEFT JOIN carrentalregistrationform crf
            ON c.Car_ID = crf.Car_ID
            AND crf.Status = 'Approved'
        ''';
        queryParams.insert(0, params['endDate']!);
        queryParams.insert(1, params['startDate']!);
        whereConditions.add('saf.SAF_ID IS NULL');
        // Admin cars (no contract) are always ok; contract cars must have contract covering the period
        whereConditions.add('(crf.Car_ID IS NULL OR (crf.StartDateTime <= ? AND crf.EndDateTime >= ?))');
        queryParams.add(params['startDate']!);
        queryParams.add(params['endDate']!);
      }

      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }

      final results = await dbService.query(query, queryParams);

      final cars = results
          .map((row) => _sanitizeRow(Map<String, dynamic>.from(row.fields)))
          .toList();

      return Response.ok(
        json.encode({'success': true, 'data': cars, 'total': cars.length}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching cars: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching cars'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
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
        // Check for duplicate license plate
        final existing = await dbService.query(
          'SELECT Car_ID FROM Cars WHERE LicensePlate = ?',
          [body['LicensePlate']]
        );
        if (existing.isNotEmpty) {
          await dbService.query('ROLLBACK');
          return Response.badRequest(
            body: json.encode({
              'success': false,
              'error': 'License plate "${body['LicensePlate']}" is already registered in the system.'
            }),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

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

        // Insert into Cars table with the thumbnail
        final carResult = await dbService.query('''
          INSERT INTO Cars 
          (LicensePlate, Seat, Manufacturer, Model, Year, Transmission, FuelType, Status, PricePerDay, ImageURL, Deposit, InspectionDate, InspectionExpiry, Odometer)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
          body['LicensePlate'],
          body['Seat'],
          body['Manufacturer'],
          body['Model'],
          body['Year'],
          body['Transmission'],
          body['FuelType'],
          body['Contract_ID'] != null
              ? CarStatus.Pending.name
              : (body['Status'] ?? CarStatus.Available.name),
          body['PricePerDay'],
          thumbnailUrl, // Use the compressed thumbnail
          body['Deposit'] ?? 0,
          body['InspectionDate'],
          body['InspectionExpiry'],
          body['Odometer'] ?? 0,
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
          body: json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final imageUrls = await _getImagesForCar(id);

      return Response.ok(
        json.encode({
          'success': true,
          'data': {'Car_ID': id, 'Images': imageUrls, 'Count': imageUrls.length}
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching car images: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching car images'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Helper method to fetch all images for a car
  Future<List<String>> _getImagesForCar(int carId) async {
    final results = await dbService.query('''
      SELECT CP_Link 
      FROM CarPictures 
      WHERE Car_ID = ?
      ORDER BY CP_ID
      ''', [carId]);

    return results.map((row) => row['CP_Link'] as String).toList();
  }
  // Get a specific car by ID with its images
  Future<Response> getCarById(Request request, String id) async {
    try {
      final carId = int.tryParse(id);
      if (carId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Fetch car details
      final carResults = await dbService.query(
        'SELECT * FROM Cars WHERE Car_ID = ?', 
        [carId]
      );

      if (carResults.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'Car not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final carData = _sanitizeRow(Map<String, dynamic>.from(carResults.first.fields));

      final imageUrls = await _getImagesForCar(carId);
      carData['Images'] = imageUrls;

      return Response.ok(
        json.encode({'success': true, 'data': carData}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching car detail: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching car detail'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
  // Update a car by ID
  Future<Response> updateCar(Request request, String id) async {
    try {
      final carId = int.tryParse(id);
      if (carId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Check if user is Admin
      if (!isAdmin(request)) {
        return Response.forbidden(
          json.encode({'success': false, 'error': 'Only administrators can update cars'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;

      // Check if car exists
      final checkCar = await dbService.query('SELECT Car_ID FROM Cars WHERE Car_ID = ?', [carId]);
      if (checkCar.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'Car not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Build update query dynamically based on provided fields
      final fields = <String>[];
      final values = <Object?>[];

      final updatableFields = [
        'Manufacturer', 'Model', 'LicensePlate', 'Year', 'Seat', 
        'Transmission', 'FuelType', 'Status', 'PricePerDay',
        'Deposit', 'InspectionDate', 'InspectionExpiry', 'Odometer'
      ];

      for (var field in updatableFields) {
        if (body.containsKey(field)) {
          fields.add('$field = ?');
          values.add(body[field]);
        }
      }

      if (fields.isEmpty) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'No fields to update'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      values.add(carId);
      final query = 'UPDATE Cars SET ${fields.join(", ")} WHERE Car_ID = ?';
      
      await dbService.query(query, values);

      return Response.ok(
        json.encode({'success': true, 'message': 'Car updated successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error updating car: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error updating car'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Get the active (Approved) rental for a car
  Future<Response> getActiveRental(Request request, String carId) async {
    try {
      final id = int.tryParse(carId);
      if (id == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query('''
        SELECT saf.SAF_ID, saf.StartDate, saf.EndDate, saf.Status,
               u.FirstName, u.LastName, u.UserName
        FROM serviceapplicationform saf
        JOIN users u ON u.User_ID = saf.User_ID
        WHERE saf.Car_ID = ? AND saf.Status = 'Approved'
        ORDER BY saf.StartDate DESC
        LIMIT 1
      ''', [id]);

      if (results.isEmpty) {
        return Response.ok(
          json.encode({'success': true, 'data': null}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final rental = Map<String, dynamic>.from(results.first.fields);
      return Response.ok(
        json.encode({'success': true, 'data': rental}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching active rental: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching active rental'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // Delete a car by ID
  Future<Response> deleteCar(Request request, String id) async {
    try {
      final carId = int.tryParse(id);
      if (carId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid car ID format'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      if (!isAdmin(request)) {
        return Response.forbidden(
          json.encode({'success': false, 'error': 'Only administrators can delete cars'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Check if car has any active (Approved) rental
      final activeRentals = await dbService.query(
        "SELECT SAF_ID FROM serviceapplicationform WHERE Car_ID = ? AND Status = 'Approved'",
        [carId]
      );
      if (activeRentals.isNotEmpty) {
        return Response.badRequest(
          body: json.encode({
            'success': false,
            'error': 'Cannot delete a car with an active rental. Complete or cancel the rental first.'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      await dbService.query('START TRANSACTION');
      try {
        // Delete related pictures
        await dbService.query('DELETE FROM CarPictures WHERE Car_ID = ?', [carId]);
        // Delete the car
        final result = await dbService.query('DELETE FROM Cars WHERE Car_ID = ?', [carId]);

        if (result.affectedRows == 0) {
          await dbService.query('ROLLBACK');
          return Response.notFound(
            json.encode({'success': false, 'error': 'Car not found'}),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        await dbService.query('COMMIT');
        return Response.ok(
          json.encode({'success': true, 'message': 'Car deleted successfully'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } catch (e) {
        await dbService.query('ROLLBACK');
        rethrow;
      }
    } catch (e) {
      print('Error deleting car: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error deleting car'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<Response> updateCarStatus(Request request, String carId) async {
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

      final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;
      final newStatus = body['status'] as String?;

      // Validate status
      if (newStatus == null || !CarStatus.values.map((e) => e.name).contains(newStatus)) {
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
        [newStatus, id]
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
