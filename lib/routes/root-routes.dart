import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../handlers/car_handlers.dart';
import '../handlers/user_handlers.dart';
import '../auth/auth.dart';
import '../handlers/image_handlers.dart';
import '../handlers/rental_handlers.dart';
import '../handlers/notification_handlers.dart';

Router getRootRoutes() {
  final router = Router();
  final userHandlers = UserHandlers();
  final carHandlers = CarHandlers();
  final rentalHandlers = RentalHandlers();
  final notificationHandlers = NotificationHandlers();

  // Public routes
  router.post('/register', registerHandler);
  router.post('/login', loginHandler);
  router.post('/upload-image', uploadImageHandler);

  // Protected routes
  final protectedRouter = Router();
  protectedRouter.post('/change-password', changePasswordHandler);
  protectedRouter.get('/me', userHandlers.getCurrentUser);
  protectedRouter.put('/update-profile', userHandlers.updateUserProfile);
  protectedRouter.get('/available-cars', carHandlers.getAllCars);
  // protectedRouter.get('/cars/<id>', getCarHandler);
  protectedRouter.get('/rental-history', carHandlers.getRentalHistory);
  protectedRouter.post('/rental-registration', carHandlers.createRentalRegistration);
  protectedRouter.get('/rental-applications', carHandlers.getAllRentalApplications);
  protectedRouter.get('/rental-applications/<id>', carHandlers.getRentalApplicationById);
  protectedRouter.put('/rental-applications/<id>/status', rentalHandlers.updateRentalStatus);
  protectedRouter.post('/notifications/register-token', notificationHandlers.registerFCMToken);
  protectedRouter.post('/add-admin-car', carHandlers.addCar);
  protectedRouter.get('/cars/<carId>/images', carHandlers.getCarImages);
  protectedRouter.get('/car-partner-registrations', carHandlers.getAllPartnerApplications);
  protectedRouter.get('/car-partner-registration/<id>', carHandlers.getPartnerApplicationById);

  router.mount('/', Pipeline()
    .addMiddleware(authMiddleware)
    .addHandler(protectedRouter));

  return router;
}
