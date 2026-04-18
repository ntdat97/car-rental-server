enum CarStatus {
  Available,    // Ready for booking
  Rented,       // Currently being used
  Expired,      // Contract period ended
  Unavailable,  // Manually disabled
  Pending,      // Awaiting approval
  Maintenance   // Under maintenance
}

enum ServiceStatus {
  Pending,
  Approved,
  Active,
  Rejected,
  Completed,
  Cancelled,
  Conflicted
}

enum ChecklistItemStatus {
  OK,
  Damaged,
  Missing
}

// Add other enums here as needed
