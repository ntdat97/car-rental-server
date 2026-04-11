import 'package:car_rental_server/handlers/partner_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../handlers/car_handlers.dart';
import '../handlers/user_handlers.dart';
import '../handlers/admin_user_handlers.dart';
import '../auth/auth.dart';
import '../handlers/image_handlers.dart';
import '../handlers/rental_handlers.dart';
import '../handlers/notification_handlers.dart';
import '../handlers/checklist_handlers.dart';
import '../handlers/user_document_handlers.dart';

Router getRootRoutes() {
  final router = Router();
  final userHandlers = UserHandlers();
  final carHandlers = CarHandlers();
  final rentalHandlers = RentalHandlers();
  final notificationHandlers = NotificationHandlers();
  final partnerHandlers = PartnerHandlers();
  final adminUserHandlers = AdminUserHandlers();
  final checklistHandlers = ChecklistHandlers();
  final userDocumentHandlers = UserDocumentHandlers();

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
  protectedRouter.get('/cars/<id>', carHandlers.getCarById);
  protectedRouter.put('/cars/<id>', carHandlers.updateCar);
  protectedRouter.delete('/cars/<id>', carHandlers.deleteCar);
  protectedRouter.get('/rental-history', rentalHandlers.getRentalHistory);
  protectedRouter.post('/rental-registration', rentalHandlers.createRentalRegistration);
  protectedRouter.get('/rental-applications', rentalHandlers.getAllRentalApplications);
  protectedRouter.get('/rental-applications/<id>', rentalHandlers.getRentalApplicationById);
  protectedRouter.get('/rental-applications/<id>/conflicts', rentalHandlers.getConflicts);
  protectedRouter.put('/rental-applications/<id>/resolve-conflict', rentalHandlers.resolveConflict);
  protectedRouter.put('/rental-applications/<id>/status', rentalHandlers.updateRentalStatus);
  protectedRouter.get('/checklist-template', checklistHandlers.getChecklistTemplate);
  protectedRouter.post('/checklist-template', checklistHandlers.addChecklistTemplateItem);
  protectedRouter.put('/checklist-template/reorder', checklistHandlers.reorderChecklistTemplate);
  protectedRouter.put('/checklist-template/<id>', checklistHandlers.updateChecklistTemplateItem);
  protectedRouter.delete('/checklist-template/<id>', checklistHandlers.deleteChecklistTemplateItem);
  protectedRouter.post('/rental-applications/<id>/pre-checklist', checklistHandlers.savePreChecklist);
  protectedRouter.get('/rental-applications/<id>/pre-checklist', checklistHandlers.getPreChecklist);
  protectedRouter.post('/rental-applications/<id>/post-checklist', checklistHandlers.savePostChecklist);
  protectedRouter.get('/rental-applications/<id>/post-checklist', checklistHandlers.getPostChecklist);
  protectedRouter.post('/rental-applications/<id>/penalties', checklistHandlers.savePenalties);
  protectedRouter.get('/rental-applications/<id>/penalties', checklistHandlers.getPenalties);
  protectedRouter.get('/rental-applications/<id>/financial-summary', checklistHandlers.getFinancialSummary);
  protectedRouter.post('/notifications/register-token', notificationHandlers.registerFCMToken);
  protectedRouter.post('/add-admin-car', carHandlers.addCar);
  protectedRouter.get('/cars/<carId>/images', carHandlers.getCarImages);
  protectedRouter.get('/cars/<carId>/active-rental', carHandlers.getActiveRental);
  protectedRouter.get('/car-partner-registrations', partnerHandlers.getAllPartnerApplications);
  protectedRouter.get('/car-partner-registration/<id>', partnerHandlers.getPartnerApplicationById);
  protectedRouter.put('/car-partner-registration/<id>/status', partnerHandlers.updatePartnerRentalStatus);

  // User document routes (self-service)
  protectedRouter.get('/me/documents', userDocumentHandlers.getMyDocuments);
  protectedRouter.post('/me/documents', userDocumentHandlers.uploadMyDocument);
  protectedRouter.delete('/me/documents/<docId>', userDocumentHandlers.deleteMyDocument);

  // Admin user document routes
  protectedRouter.get('/users/<userId>/documents', userDocumentHandlers.getUserDocuments);
  protectedRouter.post('/users/<userId>/documents', userDocumentHandlers.uploadUserDocument);
  protectedRouter.delete('/users/<userId>/documents/<docId>', (Request request, String userId, String docId) => userDocumentHandlers.deleteUserDocument(request, userId, docId));

  // Admin user management routes
  protectedRouter.get('/admin/users', adminUserHandlers.getUsers);
  protectedRouter.get('/admin/users/<id>', adminUserHandlers.getUserById);
  protectedRouter.post('/admin/users', adminUserHandlers.createUser);
  protectedRouter.put('/admin/users/<id>', adminUserHandlers.updateUser);
  protectedRouter.put('/admin/users/<id>/ban', adminUserHandlers.banUser);
  protectedRouter.put('/admin/users/<id>/unban', adminUserHandlers.unbanUser);
  protectedRouter.delete('/admin/users/<id>', adminUserHandlers.deleteUser);
  protectedRouter.put('/admin/users/<id>/reset-password', adminUserHandlers.resetPassword);

  router.mount('/', Pipeline()
    .addMiddleware(authMiddleware)
    .addHandler(protectedRouter));

  return router;
}
