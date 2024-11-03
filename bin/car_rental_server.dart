import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:car_rental_server/routes/root-routes.dart';
import 'package:car_rental_server/services/service_locator.dart';
import 'package:firebase_admin/firebase_admin.dart';

void main() async {
  // Load environment variables
  var env = DotEnv(includePlatformEnvironment: true)..load();

  // Initialize ServiceLocator
  await serviceLocator.setup();

  // Use environment variables
  final host = env['HOST'] ?? 'localhost';
  final port = int.parse(env['PORT'] ?? '8080');

  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler(getRootRoutes());

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server running on $host:${server.port}');
  var credential = Credentials.applicationDefault();
credential ??= await Credentials.login();
  // Initialize Firebase Admin
  await FirebaseAdmin.instance.initializeApp(AppOptions(
      credential: credential,
      projectId: env['FIREBASE_PROJECT_ID'] ?? ''));
  // Ensure the database connection is closed when the server shuts down
  ProcessSignal.sigint.watch().first.then((_) async {
    await serviceLocator.databaseService.close();
    exit(0);
  });
}
