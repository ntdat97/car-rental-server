import 'database_service.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late DatabaseService databaseService;

  Future<void> setup() async {
    databaseService = DatabaseService();
    await databaseService.connect();
  }
}

final serviceLocator = ServiceLocator();
