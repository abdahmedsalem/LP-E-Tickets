import 'carnet_type.dart';
import '../portfolio/face_line.dart';

class CarnetFlowData {
  const CarnetFlowData({required this.types, required this.faces});
  final List<CarnetType> types;
  final List<FaceLine> faces;
}
