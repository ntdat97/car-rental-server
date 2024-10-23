import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../handlers/car_handlers.dart';
import '../handlers/user_handlers.dart';
import '../auth/auth.dart';

Router getRootRoutes() {
  final router = Router();
  final userHandlers = UserHandlers();

  // Public routes
  router.post('/register', registerHandler);
  router.post('/login', loginHandler);

  // Protected routes
  final protectedRouter = Router();
  protectedRouter.get('/me', userHandlers.getCurrentUser);
  protectedRouter.get('/cars', listCarsHandler);
  protectedRouter.get('/cars/<id>', getCarHandler);
  protectedRouter.get('/rental-history', getRentalHistoryHandler);

  router.mount('/', Pipeline()
    .addMiddleware(authMiddleware)
    .addHandler(protectedRouter));

  return router;
}
