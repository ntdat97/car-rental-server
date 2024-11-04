import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import '../models/rental_history_dto.dart';
import '../models/car_rental_registration_dto.dart';
import 'dart:io';

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
      final rentalForm = CarRentalRegistrationDto.fromJson(body);

      final carResults = await dbService.query(
        'SELECT Status FROM cars WHERE Car_ID = ?',
        [rentalForm.carId]
      );

      if (carResults.isEmpty) {
        return Response.badRequest(body: 'Car not found');
      }

      if (carResults.first['Status'] != 'Available') {
        return Response.badRequest(body: 'Car is not available for rental');
      }

      final result = await dbService.query(
        '''
        INSERT INTO carrentalregistrationform 
        (StartDate, PickupTime, EndDate, ReturnTime, Status, User_ID, Car_ID, PaymentMethod, TotalAmount)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          rentalForm.startDate,
          rentalForm.pickupTime,
          rentalForm.endDate,
          rentalForm.returnTime,
          rentalForm.status,
          rentalForm.userId,
          rentalForm.carId,
          rentalForm.paymentMethod,
          rentalForm.totalAmount,
        ]
      );

      await dbService.query(
        'UPDATE cars SET Status = ? WHERE Car_ID = ?',
        ['Reserved', rentalForm.carId]
      );

      return Response.ok(
        json.encode({
          'success': true,
          'message': 'Rental registration created successfully',
          'registration_id': result.insertId
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'}
      );
    } catch (e) {
      print('Error creating rental registration: $e');
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Error creating rental registration'
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'}
      );
    }
  }
}
