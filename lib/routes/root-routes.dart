import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../handlers/car_handlers.dart';
import '../handlers/user_handlers.dart';
import '../auth/auth.dart';
import '../handlers/image_handlers.dart';

Router getRootRoutes() {
  final router = Router();
  final userHandlers = UserHandlers();

  // Public routes
  router.post('/register', registerHandler);
  router.post('/login', loginHandler);
    router.post('/upload-image', uploadImageHandler);

  // Protected routes
  final protectedRouter = Router();
  protectedRouter.post('/change-password', changePasswordHandler);
  protectedRouter.get('/me', userHandlers.getCurrentUser);
  protectedRouter.put('/update-profile', userHandlers.updateUserProfile);
  protectedRouter.get('/cars', listCarsHandler);
  protectedRouter.get('/cars', listCarsHandler);
  protectedRouter.get('/cars/<id>', getCarHandler);
  protectedRouter.get('/rental-history', getRentalHistoryHandler);
  protectedRouter.post('/rental-registration', createRentalRegistrationHandler);


  router.mount('/', Pipeline()
    .addMiddleware(authMiddleware)
    .addHandler(protectedRouter));

  return router;
}
