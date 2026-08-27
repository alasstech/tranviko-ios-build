/// Navigation arguments for bus selection screen.
///
/// This class provides type-safe navigation arguments to prevent runtime errors
/// when passing data between screens.
class BusSelectionArgs {
  final String departure;
  final String destination;
  final DateTime date;
  final int passengerCount;

  const BusSelectionArgs({
    required this.departure,
    required this.destination,
    required this.date,
    required this.passengerCount,
  });

  /// Convert to a Map for navigation arguments.
  /// Useful for backward compatibility with untyped navigation.
  Map<String, dynamic> toMap() => {
    'departure': departure,
    'destination': destination,
    'date': date.toIso8601String(),
    'passengerCount': passengerCount,
  };

  /// Create from a Map (typically from Navigator arguments).
  factory BusSelectionArgs.fromMap(Map<String, dynamic> map) =>
      BusSelectionArgs(
        departure: map['departure'] as String,
        destination: map['destination'] as String,
        date: DateTime.parse(map['date'] as String),
        passengerCount: map['passengerCount'] as int,
      );

  @override
  String toString() =>
      'BusSelectionArgs(departure: $departure, destination: $destination, date: $date, passengerCount: $passengerCount)';
}
