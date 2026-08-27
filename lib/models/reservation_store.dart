import '../services/local_cache_service.dart';
import '../services/push_notification_service.dart';

class Reservation {
  final String id;
  final String departure;
  final String destination;
  final String date;
  final String time;
  final String busType;
  final String pricePerSeat;
  final List<int> seats;
  final String status;
  final String qrData;
  final String paymentMethod;
  final String payerPhone;
  final List<Map<String, String>> passengers;
  final bool isCancelled;
  final bool canOpenTicket;
  final bool canOpenTripChat;
  final bool hasFeedback;
  final String companyId;
  final String companyName;
  final String refundStatus;
  final int refundAmount;
  final int retainedServiceFee;
  final String refundReference;
  final bool bookedAsGuest;
  final bool guestClaimed;
  final String guestAccessToken;
  final bool pendingGuestClaim;

  Reservation({
    required this.id,
    required this.departure,
    required this.destination,
    required this.date,
    required this.time,
    required this.busType,
    required this.pricePerSeat,
    required this.seats,
    required this.status,
    required this.qrData,
    required this.paymentMethod,
    required this.payerPhone,
    required this.passengers,
    this.isCancelled = false,
    this.canOpenTicket = true,
    this.canOpenTripChat = true,
    this.hasFeedback = false,
    this.companyId = '',
    this.companyName = 'Tranviko',
    this.refundStatus = '',
    this.refundAmount = 0,
    this.retainedServiceFee = 0,
    this.refundReference = '',
    this.bookedAsGuest = false,
    this.guestClaimed = false,
    this.guestAccessToken = '',
    this.pendingGuestClaim = false,
  });

  static List<int> _readSeats(dynamic value) {
    if (value is! Iterable) return <int>[];
    return value
        .map((seat) => seat is int ? seat : int.tryParse(seat.toString()))
        .whereType<int>()
        .toList();
  }

  static List<Map<String, String>> _readPassengers(dynamic value) {
    if (value is! Iterable) return <Map<String, String>>[];
    return value.whereType<Map>().map((passenger) {
      return passenger.map(
        (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
      );
    }).toList();
  }

  factory Reservation.fromMap(Map<String, dynamic> map) {
    final bus = map['bus'] is Map ? map['bus'] as Map : null;
    final company = map['company'] is Map ? map['company'] as Map : null;
    final cancellation = map['cancellation'] is Map
        ? map['cancellation'] as Map
        : null;
    final status = (map['status'] ?? 'Confirmee').toString();
    final cancelled =
        map['isCancelled'] == true ||
        status == 'Annulee' ||
        status == 'Annulée' ||
        status == 'Annule' ||
        status == 'Annulé';
    return Reservation(
      id: (map['id'] ?? '000000').toString(),
      departure: (map['departure'] ?? '').toString(),
      destination: (map['destination'] ?? '').toString(),
      date: (map['date'] ?? '').toString(),
      time: (bus != null ? bus['time'] ?? '' : map['time'] ?? '').toString(),
      busType: (bus != null ? bus['type'] ?? '' : map['busType'] ?? '')
          .toString(),
      pricePerSeat:
          (bus != null ? bus['price'] ?? '' : map['pricePerSeat'] ?? '')
              .toString(),
      seats: _readSeats(map['selectedSeats'] ?? map['seats']),
      status: status,
      qrData: (map['qrData'] ?? map['code'] ?? 'TICKET-000').toString(),
      paymentMethod: (map['paymentMethod'] ?? 'Orange Money').toString(),
      payerPhone: (map['payerPhone'] ?? '').toString(),
      passengers: _readPassengers(map['passengers']),
      isCancelled: cancelled,
      canOpenTicket: map['canOpenTicket'] != false && !cancelled,
      canOpenTripChat: map['canOpenTripChat'] != false && !cancelled,
      hasFeedback: map['hasFeedback'] == true,
      companyId: (company?['id'] ?? map['companyId'] ?? '').toString(),
      companyName: (company?['name'] ?? map['companyName'] ?? 'Tranviko')
          .toString(),
      refundStatus: (cancellation?['status'] ?? map['paymentStatus'] ?? '')
          .toString(),
      refundAmount: (cancellation?['refundAmount'] as num?)?.toInt() ?? 0,
      retainedServiceFee:
          (cancellation?['retainedServiceFee'] as num?)?.toInt() ?? 0,
      refundReference: (cancellation?['refundReference'] ?? '').toString(),
      bookedAsGuest: map['bookedAsGuest'] == true,
      guestClaimed: map['guestClaimed'] == true,
      guestAccessToken: (map['guestAccessToken'] ?? '').toString(),
      pendingGuestClaim: map['pendingGuestClaim'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'departure': departure,
      'destination': destination,
      'date': date,
      'time': time,
      'busType': busType,
      'pricePerSeat': pricePerSeat,
      'seats': seats,
      'status': status,
      'qrData': qrData,
      'paymentMethod': paymentMethod,
      'payerPhone': payerPhone,
      'passengers': passengers,
      'isCancelled': isCancelled,
      'canOpenTicket': canOpenTicket,
      'canOpenTripChat': canOpenTripChat,
      'hasFeedback': hasFeedback,
      'companyId': companyId,
      'companyName': companyName,
      'paymentStatus': refundStatus,
      'cancellation': refundStatus.isEmpty
          ? null
          : {
              'status': refundStatus,
              'refundAmount': refundAmount,
              'retainedServiceFee': retainedServiceFee,
              'refundReference': refundReference,
            },
      'company': {'id': companyId, 'name': companyName},
      'bookedAsGuest': bookedAsGuest,
      'guestClaimed': guestClaimed,
      if (guestAccessToken.isNotEmpty) 'guestAccessToken': guestAccessToken,
      if (pendingGuestClaim) 'pendingGuestClaim': true,
    };
  }
}

class ReservationStore {
  static final List<Reservation> reservations = [];

  static Future<void> loadFromCache() async {
    final cached = await LocalCacheService.readList('reservations_cache');
    reservations
      ..clear()
      ..addAll(cached.map(Reservation.fromMap));
    try {
      await PushNotificationService.scheduleTicketDepartureReminders(
        reservations.map((item) => item.toMap()).toList(),
      );
    } catch (_) {
      // Cache restore must remain available before notification initialization.
    }
  }

  static Future<void> replaceAll(List<Map<String, dynamic>> items) async {
    reservations
      ..clear()
      ..addAll(items.map(Reservation.fromMap));
    await _persist();
  }

  static Future<void> mergeAll(List<Map<String, dynamic>> items) async {
    final local = reservations.map((item) => item.toMap()).toList();
    final localByKey = <String, Map<String, dynamic>>{
      for (final item in local) _itemKey(item): item,
    };
    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final remote in items) {
      final key = _itemKey(remote);
      final cached = localByKey[key];
      final value = <String, dynamic>{...?cached, ...remote};
      if (!remote.containsKey('guestAccessToken') &&
          (cached?['guestAccessToken']?.toString() ?? '').isNotEmpty) {
        value['guestAccessToken'] = cached!['guestAccessToken'];
      }
      if (cached?['bookedAsGuest'] == true) value['bookedAsGuest'] = true;
      merged.add(value);
      seen.add(key);
    }
    for (final cached in local) {
      if (seen.add(_itemKey(cached))) merged.add(cached);
    }

    reservations
      ..clear()
      ..addAll(merged.map(Reservation.fromMap));
    await _persist();
  }

  static Future<List<Map<String, dynamic>>> readAnonymousReservations() {
    return LocalCacheService.readListForScope(
      'anonymous',
      'reservations_cache',
    );
  }

  static Future<void> importAnonymousReservations(
    List<Map<String, dynamic>> items,
    Map<String, dynamic> user,
  ) async {
    final matching = items
        .where((item) => _matchesUserIdentity(item, user))
        .toList();
    if (matching.isEmpty) return;
    await mergeAll(
      matching
          .map(
            (item) => <String, dynamic>{
              ...item,
              'bookedAsGuest': true,
              'pendingGuestClaim': true,
            },
          )
          .toList(),
    );
  }

  static String _itemKey(Map<String, dynamic> item) {
    final id = item['id']?.toString().trim() ?? '';
    if (id.isNotEmpty && id != '000000') return 'id:$id';
    return 'qr:${item['qrData'] ?? item['code'] ?? ''}';
  }

  static bool _matchesUserIdentity(
    Map<String, dynamic> reservation,
    Map<String, dynamic> user,
  ) {
    String phoneKey(dynamic value) {
      final digits = value?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
      if (digits.length == 8) return '223$digits';
      return digits;
    }

    final identities = <String>{
      phoneKey(user['phone']),
      phoneKey(user['username']),
    }..remove('');
    final reservationPhones = <String>{phoneKey(reservation['payerPhone'])}
      ..remove('');
    final passengerEmails = <String>{};
    final passengers = reservation['passengers'];
    if (passengers is Iterable) {
      for (final passenger in passengers.whereType<Map>()) {
        final phone = phoneKey(passenger['phone']);
        if (phone.isNotEmpty) reservationPhones.add(phone);
        final email = passenger['email']?.toString().trim().toLowerCase() ?? '';
        if (email.isNotEmpty) passengerEmails.add(email);
      }
    }
    final email = user['email']?.toString().trim().toLowerCase() ?? '';
    return identities.intersection(reservationPhones).isNotEmpty ||
        (email.isNotEmpty && passengerEmails.contains(email));
  }

  static Future<void> addReservation(Reservation reservation) async {
    reservations.removeWhere(
      (item) => item.qrData == reservation.qrData || item.id == reservation.id,
    );
    reservations.insert(0, reservation);
    await _persist();
  }

  static Future<void> persist() => _persist();

  static Future<void> _persist() async {
    final payload = reservations.map((item) => item.toMap()).toList();
    await LocalCacheService.writeList('reservations_cache', payload);
    try {
      await PushNotificationService.scheduleTicketDepartureReminders(payload);
    } catch (_) {
      // Les rappels locaux ne doivent jamais casser la confirmation du billet.
    }
  }

  static Reservation? findByCode(String code) {
    try {
      return reservations.firstWhere((element) => element.qrData == code);
    } catch (_) {
      return null;
    }
  }
}
