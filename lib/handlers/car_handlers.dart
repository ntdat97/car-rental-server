import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import 'dart:io';
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

      final cars =
          results.map((row) => Map<String, dynamic>.from(row.fields)).toList();

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
          body['Status'] ?? 'Available',
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

      final carData = Map<String, dynamic>.from(carResults.first.fields);

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
        'Transmission', 'FuelType', 'Status', 'PricePerDay'
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
}
