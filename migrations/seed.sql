-- ============================================================
-- Reset & Seed Script for car_rental database
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- Erase all data (order matters for FK, but FK checks are off)
TRUNCATE TABLE `additionalpenalties`;
TRUNCATE TABLE `postrentalimages`;
TRUNCATE TABLE `prerentalimages`;
TRUNCATE TABLE `postrentalchecklist`;
TRUNCATE TABLE `prerentalchecklist`;
TRUNCATE TABLE `userdocuments`;
TRUNCATE TABLE `userfcmtokens`;
TRUNCATE TABLE `rentalreviews`;
TRUNCATE TABLE `carrentalregistrationform`;
TRUNCATE TABLE `serviceapplicationform`;
TRUNCATE TABLE `carpictures`;
TRUNCATE TABLE `cars`;
TRUNCATE TABLE `contractdetail`;
TRUNCATE TABLE `contract`;
TRUNCATE TABLE `effectivedate`;
TRUNCATE TABLE `price`;
TRUNCATE TABLE `service`;
TRUNCATE TABLE `rentalhistory`;
TRUNCATE TABLE `drivinglicense`;
TRUNCATE TABLE `licensepictures`;
TRUNCATE TABLE `driverapplicationform`;
TRUNCATE TABLE `users`;
TRUNCATE TABLE `kindofuser`;
TRUNCATE TABLE `checklisttemplate`;
TRUNCATE TABLE `kindofcar`;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- Seed: kindofcar
-- ============================================================
INSERT INTO `kindofcar` (`Identifier_1`, `KindName`) VALUES
  (1, 'Sedan'),
  (2, 'SUV'),
  (3, 'Hatchback'),
  (4, 'Luxury'),
  (5, 'Van');

-- ============================================================
-- Seed: checklisttemplate
-- ============================================================
INSERT INTO `checklisttemplate` (`Item_ID`, `ItemName`, `IsDefault`, `SortOrder`) VALUES
  (1,  'Front Lights',         1,  1),
  (2,  'Rear Lights',          1,  2),
  (3,  'Seats',                1,  3),
  (4,  'Tires',                1,  4),
  (5,  'Side Mirrors',         1,  5),
  (6,  'Rearview Mirror',      1,  6),
  (7,  'Air Conditioning',     1,  7),
  (8,  'Exterior Body',        1,  8),
  (9,  'Interior',             1,  9),
  (10, 'Engine',               1, 10),
  (11, 'Brakes',               1, 11),
  (12, 'Windshield',           1, 12),
  (13, 'Dashboard & Controls', 1, 13);
