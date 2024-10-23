import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart';

class DatabaseService {
  late MySqlConnection _connection;
  late DotEnv _env;

  DatabaseService() {
    _env = DotEnv()..load();
  }

  Future<void> connect() async {
    final settings = ConnectionSettings(
      host: _env['DB_HOST'] ?? 'localhost',
      port: int.parse(_env['DB_PORT'] ?? '3306'),
      user: _env['DB_USER'] ?? 'root',
      password: _env['DB_PASSWORD'] ?? '',
      db: _env['DB_NAME'] ?? 'car_rental',
    );

    try {
      _connection = await MySqlConnection.connect(settings);
      print('Database connected successfully');
    } catch (e) {
      print('Failed to connect to the database: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    await _connection.close();
    print('Database connection closed');
  }

  Future<Results> query(String sql, [List<Object?>? params]) async {
    return await _connection.query(sql, params);
  }

  // Add more database methods as needed
}
