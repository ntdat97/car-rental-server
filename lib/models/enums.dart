enum CarStatus {
  Available,    // Ready for booking
  Renting,      // Currently being used
  Expired,      // Contract period ended
  Unavailable,  // Manually disabled
  Pending       // Awaiting approval
}

enum ServiceStatus {
  Pending,
  Approved,
  Rejected,
  Completed,
  Cancelled
}

// Add other enums here as needed
