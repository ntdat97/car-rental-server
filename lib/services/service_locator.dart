import 'database_service.dart';
import 'image_service.dart';
import 'fcm_service.dart';
import 'scheduled_task_service.dart';
import 'dart:async';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late DatabaseService databaseService;
  late ImageService imageService;
  late FCMService fcmService;
  late ScheduledTaskService scheduledTaskService;

  Future<void> setup() async {
    databaseService = DatabaseService();
    await databaseService.connect();
    
    imageService = ImageService();
    fcmService = await FCMService.getInstance();
    scheduledTaskService = ScheduledTaskService(databaseService);

    // Schedule status updates to run periodically
    Timer.periodic(Duration(hours: 1), (_) {
      scheduledTaskService.updateCarStatuses();
    });
  }
}

final serviceLocator = ServiceLocator();
