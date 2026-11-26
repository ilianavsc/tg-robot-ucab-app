import 'package:flutter/foundation.dart';

import '../../core/models/estado.dart';
import '../../core/models/ultrasonido.dart';
import '../../core/mqtt/mqtt_service.dart';

/// Una lectura guardada en el **historial de datos**.
@immutable
class LecturaHistorial {
  const LecturaHistorial({
    required this.hora,
    required this.numero,
    required this.modo,
    required this.bateria,
    required this.bateriaV,
    required this.lineaMm,
    required this.vIzq,
    required this.vDer,
    this.frenteCm,
    this.atrasCm,
  });

  final DateTime hora;
  final int numero;
  final String modo;
  final int bateria;
  final double bateriaV;
  final double lineaMm;
  final double vIzq;
  final double vDer;
  final double? frenteCm;
  final double? atrasCm;
}

/// **Historial de datos** (Modo Desarrollador): registro en memoria de las
/// últimas lecturas de telemetría que publica `MqttService` (robot real o
/// Demo). Guarda como máximo [capacidad] lecturas; no persiste nada.
class HistorialDatos extends ChangeNotifier {
  HistorialDatos(this._servicio) {
    _servicio.addListener(_alCambiar);
  }

  static const int capacidad = 200;

  final MqttService _servicio;
  final List<LecturaHistorial> _lecturas = <LecturaHistorial>[];
  Estado? _ultimo;

  /// Lecturas de la más reciente a la más antigua.
  List<LecturaHistorial> get lecturas =>
      List<LecturaHistorial>.unmodifiable(_lecturas.reversed);

  int get total => _lecturas.length;

  void _alCambiar() {
    final Estado? e = _servicio.ultimoEstado;
    if (e == null || identical(e, _ultimo)) return;
    _ultimo = e;
    // Estado base en cero (al detener la Demo): no es una lectura real.
    if (e.numero == 0 && e.t == 0) return;
    registrar(e, _servicio.ultimoUltrasonido);
  }

  /// Agrega una lectura (también lo usa la escucha de `MqttService`).
  void registrar(Estado e, Ultrasonido? u, {DateTime? hora}) {
    _lecturas.add(
      LecturaHistorial(
        hora: hora ?? DateTime.now(),
        numero: e.numero,
        modo: e.modo,
        bateria: e.bateria,
        bateriaV: e.bateriaV,
        lineaMm: e.lineaMm,
        vIzq: e.vIzq,
        vDer: e.vDer,
        frenteCm: u?.frenteCm,
        atrasCm: u?.atrasCm,
      ),
    );
    if (_lecturas.length > capacidad) _lecturas.removeAt(0);
    notifyListeners();
  }

  void limpiar() {
    if (_lecturas.isEmpty) return;
    _lecturas.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _servicio.removeListener(_alCambiar);
    super.dispose();
  }
}
