import 'database_service.dart';
import 'image_service.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late DatabaseService databaseService;
  late ImageService imageService;
  //late FCMService fcmService;

  Future<void> setup() async {
    databaseService = DatabaseService();
    await databaseService.connect();

    imageService = ImageService();

    //fcmService = await FCMService.getInstance();
  }
}

final serviceLocator = ServiceLocator();
