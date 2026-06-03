import '../../data/models/face_line.dart';

bool isTransferableCarnetLine(FaceLine line, int carnetSize) {
  if (carnetSize <= 0) return false;
  if (line.isExpired) return false;
  if (line.availableQty != line.initialQty) return false;
  if (line.qrActiveQty != 0) return false;
  if (line.qrBlockedQty != 0) return false;
  if (line.consumedQty != 0) return false;
  if (line.expiredQty != 0) return false;
  return line.availableQty >= carnetSize;
}

int transferableCarnetCount(FaceLine line, int carnetSize) {
  if (!isTransferableCarnetLine(line, carnetSize)) return 0;
  return line.availableQty ~/ carnetSize;
}
