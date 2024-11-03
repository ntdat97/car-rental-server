import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import '../models/rental_history_dto.dart';
import '../models/car_rental_registration_dto.dart';

Response indexHandler(Request request) {
  return Response.ok('Welcome to Car Rental Service');
}

Future<Response> listCarsHandler(Request request) async {
  // Access the user information from the request context
  final userInfo = request.context['user'] as Map<String, dynamic>?;
  
  if (userInfo == null) {
    return Response.unauthorized('User not authenticated');
  }

  final username = userInfo['username'] as String;

  final dbService = serviceLocator.databaseService;
  try {
    // You can use the username here if needed, for example:
    // final results = await dbService.query('SELECT * FROM cars WHERE owner = ?', [username]);
    
    // Or just fetch all cars if no filtering is needed:
    final results = await dbService.query('SELECT * FROM cars');
    
    final cars = results.map((row) => {
      'id': row['id'],
      'model': row['model'],
      'brand': row['brand'],
      // You could add the username here to show who's requesting:
      'requested_by': username,
    }).toList();
    
    return Response.ok(
      json.encode(cars),
      headers: {'content-type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching cars: $e');
    return Response.internalServerError(body: 'Error fetching cars');
  }
}

Future<Response> getCarHandler(Request request, String id) async {
  final dbService = serviceLocator.databaseService;
  try {
    final results = await dbService.query('SELECT * FROM cars WHERE id = ?', [id]);
    if (results.isNotEmpty) {
      final car = {
        'id': results.first['id'],
        'model': results.first['model'],
        'brand': results.first['brand'],
      };
      return Response.ok(car.toString());
    } else {
      return Response.notFound('Car not found');
    }
  } catch (e) {
    print('Error fetching car: $e');
    return Response.internalServerError(body: 'Error fetching car');
  }
}

Future<Response> getRentalHistoryHandler(Request request) async {
  final dbService = serviceLocator.databaseService;
  
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
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    print('Error fetching rental history: $e');
    return Response.internalServerError(body: 'Error fetching rental history');
  }
}

Future<Response> createRentalRegistrationHandler(Request request) async {
  final userInfo = request.context['user'] as Map<String, dynamic>?;
  
  if (userInfo == null) {
    return Response.unauthorized('User not authenticated');
  }

  try {
    final body = await json.decode(await request.readAsString()) as Map<String, dynamic>;
    final rentalForm = CarRentalRegistrationDto.fromJson(body);

    // Verify if the car exists and is available
    final carResults = await serviceLocator.databaseService.query(
      'SELECT Status FROM cars WHERE Car_ID = ?',
      [rentalForm.carId]
    );

    if (carResults.isEmpty) {
      return Response.badRequest(body: 'Car not found');
    }

    if (carResults.first['Status'] != 'Available') {
      return Response.badRequest(body: 'Car is not available for rental');
    }

    // Insert the rental registration
    final result = await serviceLocator.databaseService.query(
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

    // Update car status to 'Reserved'
    await serviceLocator.databaseService.query(
      'UPDATE cars SET Status = ? WHERE Car_ID = ?',
      ['Reserved', rentalForm.carId]
    );

    return Response.ok(
      json.encode({
        'message': 'Rental registration created successfully',
        'registration_id': result.insertId
      }),
      headers: {'content-type': 'application/json'}
    );
  } catch (e) {
    print('Error creating rental registration: $e');
    return Response.internalServerError(
      body: json.encode({'error': 'Error creating rental registration'}),
      headers: {'content-type': 'application/json'}
    );
  }
}
