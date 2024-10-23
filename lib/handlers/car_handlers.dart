import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import 'dart:convert';
import '../models/rental_history_dto.dart';

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
