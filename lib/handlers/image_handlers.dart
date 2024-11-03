import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';

Future<Response> uploadImageHandler(Request request) async {
  try {
    final bodyBytes = await request.read().toList();
    final bodyString = await utf8.decoder.bind(Stream.fromIterable(bodyBytes)).join();
    final body = json.decode(bodyString);
    
    if (body['image'] == null) {
      return Response.badRequest(
        body: json.encode({
          'success': false,
          'error': 'No image provided'
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final imageUrl = await serviceLocator.imageService.uploadImage(body['image']);
    
    if (imageUrl == null) {
      return Response.internalServerError(
        body: json.encode({
          'success': false,
          'error': 'Failed to upload image'
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      json.encode({
        'success': true,
        'url': imageUrl
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    print('Error handling image upload: $e');
    return Response.internalServerError(
      body: json.encode({
        'success': false,
        'error': 'Internal server error'
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
