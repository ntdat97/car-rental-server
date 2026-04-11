import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';
import '../auth/auth.dart';

class UserDocumentHandlers {
  final dbService = serviceLocator.databaseService;

  static const allowedCategories = [
    'id_card_front',
    'id_card_back',
    'driver_license_front',
    'driver_license_back',
    'other',
  ];

  /// GET /me/documents — List own documents
  Future<Response> getMyDocuments(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    try {
      final userId = userInfo['User_ID'] as int;
      final results = await dbService.query(
        'SELECT Doc_ID, User_ID, Category, ImageURL, UploadedAt FROM UserDocuments WHERE User_ID = ? ORDER BY Doc_ID',
        [userId],
      );

      final docs = results.map((row) => {
        'Doc_ID': row['Doc_ID'],
        'User_ID': row['User_ID'],
        'Category': row['Category'],
        'ImageURL': row['ImageURL'],
        'UploadedAt': row['UploadedAt']?.toString(),
      }).toList();

      return Response.ok(
        json.encode({'success': true, 'data': docs}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching own documents: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching documents'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// POST /me/documents — Upload own document
  Future<Response> uploadMyDocument(Request request) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    final userId = userInfo['User_ID'] as int;
    return _uploadDocument(request, userId);
  }

  /// DELETE /me/documents/<docId> — Delete own document
  Future<Response> deleteMyDocument(Request request, String docId) async {
    final userInfo = request.context['user'] as Map<String, dynamic>?;
    if (userInfo == null) {
      return Response.unauthorized('User not authenticated');
    }

    final userId = userInfo['User_ID'] as int;
    return _deleteDocument(docId, userId);
  }

  /// GET /users/<userId>/documents — Admin: list user's documents
  Future<Response> getUserDocuments(Request request, String userId) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    try {
      final uid = int.tryParse(userId);
      if (uid == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid user ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query(
        'SELECT Doc_ID, User_ID, Category, ImageURL, UploadedAt FROM UserDocuments WHERE User_ID = ? ORDER BY Doc_ID',
        [uid],
      );

      final docs = results.map((row) => {
        'Doc_ID': row['Doc_ID'],
        'User_ID': row['User_ID'],
        'Category': row['Category'],
        'ImageURL': row['ImageURL'],
        'UploadedAt': row['UploadedAt']?.toString(),
      }).toList();

      return Response.ok(
        json.encode({'success': true, 'data': docs}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching user documents: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error fetching documents'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  /// POST /users/<userId>/documents — Admin: upload document for user
  Future<Response> uploadUserDocument(Request request, String userId) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    final uid = int.tryParse(userId);
    if (uid == null) {
      return Response.badRequest(
        body: json.encode({'error': 'Invalid user ID'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }

    return _uploadDocument(request, uid);
  }

  /// DELETE /users/<userId>/documents/<docId> — Admin: delete user's document
  Future<Response> deleteUserDocument(Request request, String userId, String docId) async {
    if (!isAdmin(request)) {
      return Response.forbidden(json.encode({'error': 'Admin access required'}));
    }

    final uid = int.tryParse(userId);
    if (uid == null) {
      return Response.badRequest(
        body: json.encode({'error': 'Invalid user ID'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }

    return _deleteDocument(docId, uid);
  }

  // ─── Shared logic ────────────────────────────────────────────

  Future<Response> _uploadDocument(Request request, int userId) async {
    try {
      final body = json.decode(await request.readAsString()) as Map<String, dynamic>;
      final category = body['category'] as String?;
      final image = body['image'] as String?;

      if (category == null || !allowedCategories.contains(category)) {
        return Response.badRequest(
          body: json.encode({
            'error': 'Invalid category. Allowed: ${allowedCategories.join(', ')}'
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      if (image == null || image.isEmpty) {
        return Response.badRequest(
          body: json.encode({'error': 'Image data is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Upload to ImgBB
      final imageUrl = await serviceLocator.imageService.uploadImage(image);
      if (imageUrl == null) {
        return Response.internalServerError(
          body: json.encode({'error': 'Failed to upload image'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      int insertId;
      if (category == 'other') {
        // Allow multiple: always insert a new row
        final result = await dbService.query(
          'INSERT INTO UserDocuments (User_ID, Category, ImageURL) VALUES (?, ?, ?)',
          [userId, category, imageUrl],
        );
        insertId = result.insertId!;
      } else {
        // Single per category: delete existing then insert
        await dbService.query(
          'DELETE FROM UserDocuments WHERE User_ID = ? AND Category = ?',
          [userId, category],
        );
        final result = await dbService.query(
          'INSERT INTO UserDocuments (User_ID, Category, ImageURL) VALUES (?, ?, ?)',
          [userId, category, imageUrl],
        );
        insertId = result.insertId!;
      }

      // Fetch the inserted record
      final results = await dbService.query(
        'SELECT Doc_ID, Category, ImageURL, UploadedAt FROM UserDocuments WHERE Doc_ID = ?',
        [insertId],
      );

      final doc = results.first;

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'Doc_ID': doc['Doc_ID'],
            'Category': doc['Category'],
            'ImageURL': doc['ImageURL'],
            'UploadedAt': doc['UploadedAt']?.toString(),
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error uploading document: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error uploading document'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  Future<Response> _deleteDocument(String docId, int userId) async {
    try {
      final id = int.tryParse(docId);
      if (id == null) {
        return Response.badRequest(
          body: json.encode({'error': 'Invalid document ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final result = await dbService.query(
        'DELETE FROM UserDocuments WHERE Doc_ID = ? AND User_ID = ?',
        [id, userId],
      );

      if (result.affectedRows == 0) {
        return Response.notFound(
          json.encode({'error': 'Document not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      return Response.ok(
        json.encode({'success': true, 'message': 'Document deleted'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error deleting document: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Error deleting document'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
