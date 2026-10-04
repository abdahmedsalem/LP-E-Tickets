import 'package:equatable/equatable.dart';

/// Business outcome of checking a QR for station consumption.
class StationQrCheckResult extends Equatable {
  const StationQrCheckResult({
    required this.canConsume,
    this.canCancel = false,
    this.reservationId,
    this.reason,
    this.publicCode,
    this.clientName,
    this.clientPhone,
    this.clientEmail,
    this.totalAmount,
  });

  final bool canConsume;
  final bool canCancel;
  final String? reservationId;
  final String? reason;
  final String? publicCode;
  final String? clientName;
  final String? clientPhone;
  final String? clientEmail;
  final double? totalAmount;

  @override
  List<Object?> get props => [
    canConsume,
    canCancel,
    reservationId,
    reason,
    publicCode,
    clientName,
    clientPhone,
    clientEmail,
    totalAmount,
  ];
}
