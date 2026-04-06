-- Migration: Checklist, Financial Calculation & Active Status
-- Run this against the car_rental database

-- ── 1. Checklist Template ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ChecklistTemplate (
  Item_ID INT AUTO_INCREMENT PRIMARY KEY,
  ItemName VARCHAR(100) NOT NULL,
  IsDefault TINYINT(1) DEFAULT 1,
  SortOrder INT NOT NULL
);

-- Seed default checklist items
INSERT INTO ChecklistTemplate (ItemName, IsDefault, SortOrder) VALUES
  ('Front Lights', 1, 1),
  ('Rear Lights', 1, 2),
  ('Seats', 1, 3),
  ('Tires', 1, 4),
  ('Side Mirrors', 1, 5),
  ('Rearview Mirror', 1, 6),
  ('Air Conditioning', 1, 7),
  ('Exterior Body', 1, 8),
  ('Interior', 1, 9),
  ('Engine', 1, 10),
  ('Brakes', 1, 11),
  ('Windshield', 1, 12),
  ('Dashboard & Controls', 1, 13);

-- ── 2. Pre-Rental Checklist ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS PreRentalChecklist (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  SAF_ID INT NOT NULL,
  Item_ID INT NULL,
  CustomItemName VARCHAR(100) NULL,
  Status ENUM('OK', 'Damaged', 'Missing') DEFAULT 'OK',
  Comment TEXT NULL,
  FOREIGN KEY (SAF_ID) REFERENCES serviceapplicationform(SAF_ID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS PreRentalImages (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  SAF_ID INT NOT NULL,
  ChecklistItem_ID INT NULL,
  ImageURL VARCHAR(500) NOT NULL,
  FOREIGN KEY (SAF_ID) REFERENCES serviceapplicationform(SAF_ID) ON DELETE CASCADE
);

-- ── 3. Post-Rental Checklist ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS PostRentalChecklist (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  SAF_ID INT NOT NULL,
  Item_ID INT NULL,
  CustomItemName VARCHAR(100) NULL,
  Status ENUM('OK', 'Damaged', 'Missing') DEFAULT 'OK',
  Comment TEXT NULL,
  DamageCost DECIMAL(15,0) DEFAULT 0,
  FOREIGN KEY (SAF_ID) REFERENCES serviceapplicationform(SAF_ID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS PostRentalImages (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  SAF_ID INT NOT NULL,
  ChecklistItem_ID INT NULL,
  ImageURL VARCHAR(500) NOT NULL,
  FOREIGN KEY (SAF_ID) REFERENCES serviceapplicationform(SAF_ID) ON DELETE CASCADE
);

-- ── 4. Additional Penalties ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS AdditionalPenalties (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  SAF_ID INT NOT NULL,
  Description VARCHAR(255) NOT NULL,
  Amount DECIMAL(15,0) NOT NULL,
  FOREIGN KEY (SAF_ID) REFERENCES serviceapplicationform(SAF_ID) ON DELETE CASCADE
);

-- ── 5. Alter SAF table ───────────────────────────────────────────────────────

ALTER TABLE serviceapplicationform
  ADD COLUMN PreOdometer INT NULL,
  ADD COLUMN PostOdometer INT NULL,
  ADD COLUMN TotalDamageCost DECIMAL(15,0) DEFAULT 0,
  ADD COLUMN TotalPenalty DECIMAL(15,0) DEFAULT 0,
  ADD COLUMN FinalAmount DECIMAL(15,0) DEFAULT 0;
