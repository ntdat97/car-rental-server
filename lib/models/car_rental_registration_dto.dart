class CarRentalRegistrationDto {
  final String startDate;
  final String pickupTime;
  final String endDate;
  final String returnTime;
  final String status;
  final int userId;
  final int carId;
  final String paymentMethod;
  final double totalAmount;

  CarRentalRegistrationDto({
    required this.startDate,
    required this.pickupTime,
    required this.endDate,
    required this.returnTime,
    required this.status,
    required this.userId,
    required this.carId,
    required this.paymentMethod,
    required this.totalAmount,
  });

  Map<String, dynamic> toJson() => {
    'start_date': startDate,
    'pickup_time': pickupTime,
    'end_date': endDate,
    'return_time': returnTime,
    'status': status,
    'user_id': userId,
    'car_id': carId,
    'payment_method': paymentMethod,
    'total_amount': totalAmount,
  };

  factory CarRentalRegistrationDto.fromJson(Map<String, dynamic> json) => 
    CarRentalRegistrationDto(
      startDate: json['start_date'],
      pickupTime: json['pickup_time'],
      endDate: json['end_date'],
      returnTime: json['return_time'],
      status: json['status'],
      userId: json['user_id'],
      carId: json['car_id'],
      paymentMethod: json['payment_method'],
      totalAmount: json['total_amount'],
    );
}
