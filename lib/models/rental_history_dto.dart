class RentalHistoryDto {
  final int id;
  final int carId;
  final int userId;
  final String rentalDate;
  final String? returnDate;

  RentalHistoryDto({
    required this.id,
    required this.carId,
    required this.userId,
    required this.rentalDate,
    this.returnDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'car_id': carId,
    'user_id': userId,
    'rental_date': rentalDate,
    'return_date': returnDate,
  };

  factory RentalHistoryDto.fromJson(Map<String, dynamic> json) => RentalHistoryDto(
    id: json['id'],
    carId: json['car_id'],
    userId: json['user_id'],
    rentalDate: json['rental_date'],
    returnDate: json['return_date'],
  );
}
