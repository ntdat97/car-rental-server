import 'package:mysql1/mysql1.dart';
import 'package:dotenv/dotenv.dart';

class DatabaseService {
  MySqlConnection? _connection;
  ConnectionSettings? _settings;
  late DotEnv _env;

  DatabaseService() {
    _env = DotEnv()..load();
  }

  Future<void> connect() async {
    _settings = ConnectionSettings(
      host: _env['DB_HOST'] ?? 'localhost',
      port: int.parse(_env['DB_PORT'] ?? '3306'),
      user: _env['DB_USER'] ?? 'root',
      password: _env['DB_PASSWORD'] ?? '',
      db: _env['DB_NAME'] ?? 'car_rental',
    );

    try {
      await _openConnection();
    } catch (e) {
      print('Failed to connect to the database: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
    print('Database connection closed');
  }

  Future<Results> query(String sql, [List<Object?>? params]) async {
    await _ensureConnected();

    try {
      return await _connection!.query(sql, params);
    } catch (e) {
      if (!_shouldReconnect(e) || _isTransactionStatement(sql)) {
        rethrow;
      }

      print('Database connection dropped, reconnecting and retrying query');
      await _reconnect();
      return await _connection!.query(sql, params);
    }
  }

  Future<void> _ensureConnected() async {
    if (_connection != null) {
      return;
    }

    await _openConnection();
  }

  Future<void> _openConnection() async {
    final settings = _settings;
    if (settings == null) {
      throw StateError('Database settings have not been initialized. Call connect() first.');
    }

    _connection = await MySqlConnection.connect(settings);
    print('Database connected successfully');
  }

  Future<void> _reconnect() async {
    await _connection?.close();
    _connection = null;
    await _openConnection();
  }

  bool _shouldReconnect(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('cannot write to socket, it is closed') ||
        message.contains('mysql server has gone away') ||
        message.contains('lost connection') ||
        message.contains('connection reset by peer') ||
        message.contains('broken pipe');
  }

  bool _isTransactionStatement(String sql) {
    final normalizedSql = sql.trimLeft().toUpperCase();
    return normalizedSql.startsWith('START TRANSACTION') ||
        normalizedSql.startsWith('BEGIN') ||
        normalizedSql.startsWith('COMMIT') ||
        normalizedSql.startsWith('ROLLBACK');
  }
}
