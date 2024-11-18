import 'package:car_rental_server/handlers/partner_handler.dart';
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
  final partnerHandlers = PartnerHandlers();

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
  protectedRouter.get('/rental-history', rentalHandlers.getRentalHistory);
  protectedRouter.post('/rental-registration', rentalHandlers.createRentalRegistration);
  protectedRouter.get('/rental-applications', rentalHandlers.getAllRentalApplications);
  protectedRouter.get('/rental-applications/<id>', rentalHandlers.getRentalApplicationById);
  protectedRouter.put('/rental-applications/<id>/status', rentalHandlers.updateRentalStatus);
  protectedRouter.post('/notifications/register-token', notificationHandlers.registerFCMToken);
  protectedRouter.post('/add-admin-car', carHandlers.addCar);
  protectedRouter.get('/cars/<carId>/images', carHandlers.getCarImages);
  protectedRouter.get('/car-partner-registrations', partnerHandlers.getAllPartnerApplications);
  protectedRouter.get('/car-partner-registration/<id>', partnerHandlers.getPartnerApplicationById);
  protectedRouter.put('/car-partner-registration/<id>/status', partnerHandlers.updatePartnerRentalStatus);

  router.mount('/', Pipeline()
    .addMiddleware(authMiddleware)
    .addHandler(protectedRouter));

  return router;
}
