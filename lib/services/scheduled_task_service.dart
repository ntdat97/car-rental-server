import 'package:car_rental_server/services/database_service.dart';

class ScheduledTaskService {
  final DatabaseService _dbService;

  ScheduledTaskService(this._dbService);

  Future<void> updateCarStatuses() async {
    final now = DateTime.now().toUtc();

    // Update contract cars status
    await _dbService.query('''
      UPDATE Cars c
      LEFT JOIN carrentalregistrationform crf ON c.Car_ID = crf.Car_ID
      SET c.Status = CASE
        -- For contract cars
        WHEN crf.Car_ID IS NOT NULL THEN
          CASE
            -- Check if contract is expired
            WHEN crf.EndDateTime < ? THEN 'Expired'
            -- Check if car is currently rented
            WHEN EXISTS (
              SELECT 1 FROM serviceapplicationform saf
              WHERE saf.Car_ID = c.Car_ID
                AND saf.Status = 'Approved'
                AND saf.StartDate <= ?
                AND saf.EndDate >= ?
            ) THEN 'Renting'
            ELSE 'Available'
          END
        -- For admin cars
        ELSE
          CASE
            WHEN EXISTS (
              SELECT 1 FROM serviceapplicationform saf
              WHERE saf.Car_ID = c.Car_ID
                AND saf.Status = 'Approved'
                AND saf.StartDate <= ?
                AND saf.EndDate >= ?
            ) THEN 'Renting'
            ELSE 'Available'
          END
      END
      WHERE c.Status NOT IN ('Unavailable', 'Pending')
    ''', [now, now, now, now, now]);
  }
} 