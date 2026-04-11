-- Allow multiple documents for 'other' category by dropping the unique constraint.
-- Must create a plain index on User_ID first because MySQL needs it to back the foreign key.
ALTER TABLE UserDocuments ADD INDEX idx_user_id (User_ID);
ALTER TABLE UserDocuments DROP INDEX idx_user_category;
