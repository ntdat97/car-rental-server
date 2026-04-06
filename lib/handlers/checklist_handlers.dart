import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../services/service_locator.dart';

class ChecklistHandlers {
  final dbService = serviceLocator.databaseService;

  // GET /checklist-template
  Future<Response> getChecklistTemplate(Request request) async {
    try {
      final results = await dbService.query(
        'SELECT * FROM ChecklistTemplate ORDER BY SortOrder ASC'
      );

      final items = results.map((row) {
        return {
          'Item_ID': row['Item_ID'],
          'ItemName': row['ItemName'],
          'IsDefault': row['IsDefault'] == 1,
          'SortOrder': row['SortOrder'],
        };
      }).toList();

      return Response.ok(
        json.encode({'success': true, 'data': items}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching checklist template: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to fetch checklist template'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // POST /checklist-template
  Future<Response> addChecklistTemplateItem(Request request) async {
    try {
      final body = await request.readAsString().then(json.decode);
      final itemName = body['ItemName'] as String?;

      if (itemName == null || itemName.trim().isEmpty) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'ItemName is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Get max sort order
      final maxSort = await dbService.query(
        'SELECT COALESCE(MAX(SortOrder), 0) as maxSort FROM ChecklistTemplate'
      );
      final nextSort = (maxSort.first['maxSort'] as int) + 1;

      final result = await dbService.query(
        'INSERT INTO ChecklistTemplate (ItemName, IsDefault, SortOrder) VALUES (?, 0, ?)',
        [itemName.trim(), nextSort]
      );

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'Item_ID': result.insertId,
            'ItemName': itemName.trim(),
            'IsDefault': false,
            'SortOrder': nextSort,
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error adding checklist template item: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to add checklist template item'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // POST /rental-applications/{id}/pre-checklist
  Future<Response> savePreChecklist(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Verify rental exists and is in Approved status
      final rental = await dbService.query(
        'SELECT Status FROM serviceapplicationform WHERE SAF_ID = ?',
        [safId]
      );
      if (rental.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'Rental application not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
      if (rental.first['Status'] != 'Approved') {
        return Response.forbidden(
          json.encode({'success': false, 'error': 'Pre-checklist can only be saved for Approved rentals'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await request.readAsString().then(json.decode);
      final items = (body['items'] as List?) ?? [];
      final images = (body['images'] as List?) ?? [];
      final odometer = body['odometer'] as int?;

      if (odometer == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Odometer reading is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Delete existing pre-checklist data for this SAF (in case of re-submit)
      await dbService.query('DELETE FROM PreRentalImages WHERE SAF_ID = ?', [safId]);
      await dbService.query('DELETE FROM PreRentalChecklist WHERE SAF_ID = ?', [safId]);

      // Save checklist items
      for (final item in items) {
        final result = await dbService.query(
          '''INSERT INTO PreRentalChecklist (SAF_ID, Item_ID, CustomItemName, Status, Comment)
             VALUES (?, ?, ?, ?, ?)''',
          [
            safId,
            item['Item_ID'],
            item['CustomItemName'],
            item['Status'] ?? 'OK',
            item['Comment'],
          ]
        );

        // Save images for this checklist item
        final itemImages = (item['Images'] as List?) ?? [];
        for (final imageUrl in itemImages) {
          await dbService.query(
            'INSERT INTO PreRentalImages (SAF_ID, ChecklistItem_ID, ImageURL) VALUES (?, ?, ?)',
            [safId, result.insertId, imageUrl]
          );
        }
      }

      // Save general inspection images (not tied to a checklist item)
      for (final imageUrl in images) {
        await dbService.query(
          'INSERT INTO PreRentalImages (SAF_ID, ChecklistItem_ID, ImageURL) VALUES (?, NULL, ?)',
          [safId, imageUrl]
        );
      }

      // Update odometer on SAF
      await dbService.query(
        'UPDATE serviceapplicationform SET PreOdometer = ? WHERE SAF_ID = ?',
        [odometer, safId]
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'Pre-rental checklist saved successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error saving pre-checklist: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to save pre-rental checklist'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // GET /rental-applications/{id}/pre-checklist
  Future<Response> getPreChecklist(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final items = await dbService.query(
        '''SELECT pc.*, ct.ItemName as TemplateName
           FROM PreRentalChecklist pc
           LEFT JOIN ChecklistTemplate ct ON pc.Item_ID = ct.Item_ID
           WHERE pc.SAF_ID = ?
           ORDER BY pc.ID ASC''',
        [safId]
      );

      final generalImages = await dbService.query(
        'SELECT * FROM PreRentalImages WHERE SAF_ID = ? AND ChecklistItem_ID IS NULL',
        [safId]
      );

      final odometer = await dbService.query(
        'SELECT PreOdometer FROM serviceapplicationform WHERE SAF_ID = ?',
        [safId]
      );

      final checklistItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemImages = await dbService.query(
          'SELECT ImageURL FROM PreRentalImages WHERE SAF_ID = ? AND ChecklistItem_ID = ?',
          [safId, item['ID']]
        );

        checklistItems.add({
          'ID': item['ID'],
          'Item_ID': item['Item_ID'],
          'ItemName': item['TemplateName'] ?? item['CustomItemName'],
          'CustomItemName': item['CustomItemName'],
          'Status': item['Status'],
          'Comment': item['Comment'],
          'Images': itemImages.map((r) => r['ImageURL']).toList(),
        });
      }

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'items': checklistItems,
            'generalImages': generalImages.map((r) => r['ImageURL']).toList(),
            'odometer': odometer.isNotEmpty ? odometer.first['PreOdometer'] : null,
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching pre-checklist: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to fetch pre-rental checklist'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // POST /rental-applications/{id}/post-checklist
  Future<Response> savePostChecklist(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Verify rental exists and is in Active status
      final rental = await dbService.query(
        'SELECT Status FROM serviceapplicationform WHERE SAF_ID = ?',
        [safId]
      );
      if (rental.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'Rental application not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
      if (rental.first['Status'] != 'Active') {
        return Response.forbidden(
          json.encode({'success': false, 'error': 'Post-checklist can only be saved for Active rentals'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await request.readAsString().then(json.decode);
      final items = (body['items'] as List?) ?? [];
      final images = (body['images'] as List?) ?? [];
      final odometer = body['odometer'] as int?;

      if (odometer == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Odometer reading is required'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      // Delete existing post-checklist data for this SAF (in case of re-submit)
      await dbService.query('DELETE FROM PostRentalImages WHERE SAF_ID = ?', [safId]);
      await dbService.query('DELETE FROM PostRentalChecklist WHERE SAF_ID = ?', [safId]);

      num totalDamageCost = 0;

      // Save checklist items
      for (final item in items) {
        final damageCost = (item['DamageCost'] as num?) ?? 0;
        totalDamageCost += damageCost;

        final result = await dbService.query(
          '''INSERT INTO PostRentalChecklist (SAF_ID, Item_ID, CustomItemName, Status, Comment, DamageCost)
             VALUES (?, ?, ?, ?, ?, ?)''',
          [
            safId,
            item['Item_ID'],
            item['CustomItemName'],
            item['Status'] ?? 'OK',
            item['Comment'],
            damageCost,
          ]
        );

        // Save images for this checklist item
        final itemImages = (item['Images'] as List?) ?? [];
        for (final imageUrl in itemImages) {
          await dbService.query(
            'INSERT INTO PostRentalImages (SAF_ID, ChecklistItem_ID, ImageURL) VALUES (?, ?, ?)',
            [safId, result.insertId, imageUrl]
          );
        }
      }

      // Save general inspection images
      for (final imageUrl in images) {
        await dbService.query(
          'INSERT INTO PostRentalImages (SAF_ID, ChecklistItem_ID, ImageURL) VALUES (?, NULL, ?)',
          [safId, imageUrl]
        );
      }

      // Update odometer and total damage cost on SAF
      await dbService.query(
        'UPDATE serviceapplicationform SET PostOdometer = ?, TotalDamageCost = ? WHERE SAF_ID = ?',
        [odometer, totalDamageCost, safId]
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'Post-rental checklist saved successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error saving post-checklist: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to save post-rental checklist'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // GET /rental-applications/{id}/post-checklist
  Future<Response> getPostChecklist(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final items = await dbService.query(
        '''SELECT pc.*, ct.ItemName as TemplateName
           FROM PostRentalChecklist pc
           LEFT JOIN ChecklistTemplate ct ON pc.Item_ID = ct.Item_ID
           WHERE pc.SAF_ID = ?
           ORDER BY pc.ID ASC''',
        [safId]
      );

      final generalImages = await dbService.query(
        'SELECT * FROM PostRentalImages WHERE SAF_ID = ? AND ChecklistItem_ID IS NULL',
        [safId]
      );

      final odometer = await dbService.query(
        'SELECT PostOdometer FROM serviceapplicationform WHERE SAF_ID = ?',
        [safId]
      );

      final checklistItems = <Map<String, dynamic>>[];
      for (final item in items) {
        final itemImages = await dbService.query(
          'SELECT ImageURL FROM PostRentalImages WHERE SAF_ID = ? AND ChecklistItem_ID = ?',
          [safId, item['ID']]
        );

        checklistItems.add({
          'ID': item['ID'],
          'Item_ID': item['Item_ID'],
          'ItemName': item['TemplateName'] ?? item['CustomItemName'],
          'CustomItemName': item['CustomItemName'],
          'Status': item['Status'],
          'Comment': item['Comment'],
          'DamageCost': item['DamageCost'],
          'Images': itemImages.map((r) => r['ImageURL']).toList(),
        });
      }

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'items': checklistItems,
            'generalImages': generalImages.map((r) => r['ImageURL']).toList(),
            'odometer': odometer.isNotEmpty ? odometer.first['PostOdometer'] : null,
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching post-checklist: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to fetch post-rental checklist'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // POST /rental-applications/{id}/penalties
  Future<Response> savePenalties(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final body = await request.readAsString().then(json.decode);
      final penalties = (body['penalties'] as List?) ?? [];

      // Delete existing penalties
      await dbService.query('DELETE FROM AdditionalPenalties WHERE SAF_ID = ?', [safId]);

      num totalPenalty = 0;

      for (final penalty in penalties) {
        final description = penalty['Description'] as String?;
        final amount = (penalty['Amount'] as num?) ?? 0;

        if (description == null || description.trim().isEmpty) continue;

        totalPenalty += amount;

        await dbService.query(
          'INSERT INTO AdditionalPenalties (SAF_ID, Description, Amount) VALUES (?, ?, ?)',
          [safId, description.trim(), amount]
        );
      }

      // Update total penalty on SAF
      await dbService.query(
        'UPDATE serviceapplicationform SET TotalPenalty = ? WHERE SAF_ID = ?',
        [totalPenalty, safId]
      );

      return Response.ok(
        json.encode({'success': true, 'message': 'Penalties saved successfully'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error saving penalties: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to save penalties'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // GET /rental-applications/{id}/penalties
  Future<Response> getPenalties(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final results = await dbService.query(
        'SELECT * FROM AdditionalPenalties WHERE SAF_ID = ? ORDER BY ID ASC',
        [safId]
      );

      final penalties = results.map((row) {
        return {
          'ID': row['ID'],
          'Description': row['Description'],
          'Amount': row['Amount'],
        };
      }).toList();

      return Response.ok(
        json.encode({'success': true, 'data': penalties}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching penalties: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to fetch penalties'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }

  // GET /rental-applications/{id}/financial-summary
  Future<Response> getFinancialSummary(Request request, String id) async {
    try {
      final safId = int.tryParse(id);
      if (safId == null) {
        return Response.badRequest(
          body: json.encode({'success': false, 'error': 'Invalid application ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final rental = await dbService.query('''
        SELECT 
          saf.StartDate, saf.EndDate,
          saf.TotalDamageCost, saf.TotalPenalty, saf.FinalAmount,
          saf.PreOdometer, saf.PostOdometer,
          c.PricePerDay, c.Deposit
        FROM serviceapplicationform saf
        JOIN Cars c ON saf.Car_ID = c.Car_ID
        WHERE saf.SAF_ID = ?
      ''', [safId]);

      if (rental.isEmpty) {
        return Response.notFound(
          json.encode({'success': false, 'error': 'Rental application not found'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

      final row = rental.first;
      final startDate = DateTime.parse(row['StartDate'].toString());
      final endDate = DateTime.parse(row['EndDate'].toString());
      final days = endDate.difference(startDate).inDays + 1;
      final pricePerDay = (row['PricePerDay'] as num).toDouble();
      final deposit = (row['Deposit'] as num?)?.toDouble() ?? 0;
      final totalDamage = (row['TotalDamageCost'] as num?)?.toDouble() ?? 0;
      final totalPenalty = (row['TotalPenalty'] as num?)?.toDouble() ?? 0;
      final rentalCost = pricePerDay * days;
      final finalAmount = rentalCost - deposit + totalDamage + totalPenalty;

      // Get penalty details
      final penalties = await dbService.query(
        'SELECT Description, Amount FROM AdditionalPenalties WHERE SAF_ID = ? ORDER BY ID ASC',
        [safId]
      );

      return Response.ok(
        json.encode({
          'success': true,
          'data': {
            'rentalCost': rentalCost,
            'deposit': deposit,
            'totalDamage': totalDamage,
            'totalPenalties': totalPenalty,
            'penaltyDetails': penalties.map((r) {
              return {'Description': r['Description'], 'Amount': r['Amount']};
            }).toList(),
            'finalAmount': finalAmount,
            'preOdometer': row['PreOdometer'],
            'postOdometer': row['PostOdometer'],
          }
        }),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    } catch (e) {
      print('Error fetching financial summary: $e');
      return Response.internalServerError(
        body: json.encode({'success': false, 'error': 'Failed to fetch financial summary'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    }
  }
}
