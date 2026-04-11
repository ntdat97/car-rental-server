CREATE TABLE UserDocuments (
  Doc_ID INT PRIMARY KEY AUTO_INCREMENT,
  User_ID INT NOT NULL,
  Category VARCHAR(50) NOT NULL,
  ImageURL VARCHAR(500) NOT NULL,
  UploadedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (User_ID) REFERENCES Users(User_ID) ON DELETE CASCADE
);

-- Each user can have one image per category
ALTER TABLE UserDocuments ADD UNIQUE INDEX idx_user_category (User_ID, Category);
