import 'dart:convert';
import 'dart:io';
import 'package:bcrypt/bcrypt.dart';
import 'package:car_rental_server/auth/auth_helpers.dart';
import 'package:car_rental_server/services/service_locator.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

final bearerTokenRegExp = RegExp(r'Bearer (?<token>.+)');
final dbService = serviceLocator.databaseService;

Middleware authMiddleware = (innerHandler) {
  return (request) {
    final reqPath = request.url.path;

    // Bypass auth header check for these routes
    if (const ['login', 'register'].contains(reqPath)) {
      return innerHandler(request);
    }

    final authHeader = request.headers[HttpHeaders.authorizationHeader] ?? '';
    final match = bearerTokenRegExp.firstMatch(authHeader);
    final jwt = match?.namedGroup('token');
    if (jwt == null) {
      return Response.unauthorized(null);
    }

    // Verify JWT token using secret key
    final decodedToken = JWT.tryVerify(jwt, jwtSecretKey);
    if (decodedToken == null) {
      return Response.unauthorized(null);
    }

    return innerHandler(request.change(
      context: {'user': decodedToken.payload},
    ));
  };
};

Future<Map<String, dynamic>?> getCurrentUserInternal(String username) async {
  try {
    final results = await dbService.query(
      'SELECT * FROM Users WHERE username = ?',
      [username]
    );

    if (results.isEmpty) {
      return null;
    }

    final userData = results.first;

    // Convert any non-JSON-serializable types (like DateTime) to strings
    final jsonSafeUserData = Map<String, dynamic>.from(userData as Map);
    jsonSafeUserData['created_at'] = userData['created_at'].toString();

    return jsonSafeUserData;
  } catch (e) {
    print('Error fetching user data: $e');
    return null;
  }
}

Future<Response> registerHandler(Request request) async {
  ({String username, String password}) reqBody;

  try {
    final body =
        await json.decode(await request.readAsString()) as Map<String, dynamic>;
    reqBody = switch (body) {
      {'username': String username, 'password': String password} => (
          username: username,
          password: password,
        ),
      _ => throw FormatException('Username & Password required for register'),
    };
  } on FormatException catch (e) {
    return Response.badRequest(body: e.message);
  }

  final userExists = await dbService.query(
    'SELECT 1 FROM Users WHERE username = ? LIMIT 1',
    [reqBody.username]
  );

  if (userExists.isNotEmpty) {
    return Response.badRequest(body: 'Username already taken.');
  }

  final hashedPassword = BCrypt.hashpw(reqBody.password, BCrypt.gensalt());
  final now = DateTime.now().toUtc();

  final result = await dbService.query(
    'INSERT INTO Users (username, password_hash, created_at) VALUES (?, ?, ?)',
    [reqBody.username, hashedPassword, now.toIso8601String()]
  );

  final userId = result.insertId; // This gets the auto-generated ID

  return Response.ok(json.encode({'message': 'User registered', 'userId': userId}));
}

Future<Response> loginHandler(Request request) async {
  ({String username, String password}) reqBody;

  try {
    final bodyString = await request.readAsString();
    final body = json.decode(bodyString) as Map<String, dynamic>;
    reqBody = switch (body) {
      {'username': String username, 'password': String password} => (
          username: username,
          password: password,
        ),
      _ => throw FormatException('Username & Password required for register'),
    };
  } on FormatException catch (e) {
    return Response.badRequest(body: e.message);
  }

  final results = await dbService.query(
    'SELECT id, password_hash FROM Users WHERE username = ?',
    [reqBody.username]
  );

  if (results.isEmpty) {
    return Response.unauthorized('Invalid user credentials');
  }

  final userFromDB = results.first;
  final passwordMatches = BCrypt.checkpw(reqBody.password, userFromDB['password_hash']);
  if (!passwordMatches) {
    return Response.unauthorized('Invalid user credentials');
  }

  // Issue a token valid for a day
  final jwtToken = JWT({
    'username': reqBody.username,
    'userId': userFromDB['id']
  }).sign(
    jwtSecretKey,
    expiresIn: const Duration(days: 1),
  );

  return Response.ok(
    jsonEncode({'token': jwtToken}),
    headers: {HttpHeaders.contentTypeHeader: 'application/json'},
  );
}
