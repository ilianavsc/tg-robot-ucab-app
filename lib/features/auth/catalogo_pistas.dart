import 'package:flutter/foundation.dart';

/// Configuración base de una pista disponible en el laboratorio.
class PistaLocal {
  const PistaLocal({
    required this.id,
    required this.nombre,
    required this.longitudM,
    this.torresControl = 0,
    this.base = false,
  });

  final String id;
  final String nombre;
  final double longitudM;

  /// Cantidad estimada de torres de control BLE (`0`, `1` o `2`). Por defecto `0` (básico sin torres).
  final int torresControl;

  /// `true` para las pistas precargadas del proyecto.
  final bool base;
}

/// Catálogo local en memoria de pistas seleccionables desde el Login.
///
/// Arranca únicamente con `Pista A (8,05 m)` y sin pista seleccionada (`activa == null`),
/// obligando a elegir o crear una pista antes de iniciar sesión.
class CatalogoPistas extends ChangeNotifier {
  CatalogoPistas() {
    _pistas.addAll(const <PistaLocal>[
      PistaLocal(
        id: 'A',
        nombre: 'Pista A · Circuito histórico',
        longitudM: 8.05,
        torresControl: 0,
        base: true,
      ),
    ]);
  }

  final List<PistaLocal> _pistas = <PistaLocal>[];
  String? _activaId;
  int _contador = 1;

  List<PistaLocal> get pistas => List<PistaLocal>.unmodifiable(_pistas);
  String? get activaId => _activaId;
  bool get tienePistaActiva => _activaId != null;

  PistaLocal? get activa {
    if (_activaId == null) return null;
    for (final PistaLocal p in _pistas) {
      if (p.id == _activaId) return p;
    }
    return null;
  }

  bool seleccionar(String id) {
    final bool existe = _pistas.any((PistaLocal p) => p.id == id);
    if (!existe || _activaId == id) return existe;
    _activaId = id;
    notifyListeners();
    return true;
  }

  /// Registra una nueva pista con torres de control (`0`, `1` o `2`), nombre y
  /// longitud (`1,0–50,0 m`) y la selecciona automáticamente como activa.
  PistaLocal? agregarPista({
    required String nombre,
    required double longitudM,
    int torresControl = 0,
  }) {
    final String limpio = nombre.trim();
    if (limpio.isEmpty || longitudM < 1.0 || longitudM > 50.0) return null;
    final int torres = torresControl.clamp(0, 2);
    final PistaLocal nueva = PistaLocal(
      id: 'P${_contador++}',
      nombre: limpio,
      longitudM: double.parse(longitudM.toStringAsFixed(2)),
      torresControl: torres,
    );
    _pistas.add(nueva);
    _activaId = nueva.id;
    notifyListeners();
    return nueva;
  }
}
