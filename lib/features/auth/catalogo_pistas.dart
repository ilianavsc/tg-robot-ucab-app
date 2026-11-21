import 'package:flutter/foundation.dart';

/// Configuración base de una pista disponible en el laboratorio.
class PistaLocal {
  const PistaLocal({
    required this.id,
    required this.nombre,
    required this.longitudM,
    this.base = false,
  });

  final String id;
  final String nombre;
  final double longitudM;

  /// `true` para las pistas base del proyecto (Pista B y Pista A).
  final bool base;
}

/// Catálogo local en memoria de pistas seleccionables desde el Login.
class CatalogoPistas extends ChangeNotifier {
  CatalogoPistas() {
    _pistas.addAll(const <PistaLocal>[
      PistaLocal(
        id: 'B',
        nombre: 'Pista B · Pasillo UCAB',
        longitudM: 9.0,
        base: true,
      ),
      PistaLocal(
        id: 'A',
        nombre: 'Pista A · Circuito histórico',
        longitudM: 8.05,
        base: true,
      ),
    ]);
  }

  final List<PistaLocal> _pistas = <PistaLocal>[];
  String _activaId = 'B';
  int _contador = 1;

  List<PistaLocal> get pistas => List<PistaLocal>.unmodifiable(_pistas);
  String get activaId => _activaId;

  PistaLocal get activa => _pistas.firstWhere(
    (PistaLocal p) => p.id == _activaId,
    orElse: () => _pistas.first,
  );

  bool seleccionar(String id) {
    final bool existe = _pistas.any((PistaLocal p) => p.id == id);
    if (!existe || _activaId == id) return existe;
    _activaId = id;
    notifyListeners();
    return true;
  }

  /// Registra una nueva pista con nombre y longitud (1,0–50,0 m) y la activa.
  PistaLocal? agregarPista({
    required String nombre,
    required double longitudM,
  }) {
    final String limpio = nombre.trim();
    if (limpio.isEmpty || longitudM < 1.0 || longitudM > 50.0) return null;
    final PistaLocal nueva = PistaLocal(
      id: 'P${_contador++}',
      nombre: limpio,
      longitudM: double.parse(longitudM.toStringAsFixed(2)),
    );
    _pistas.add(nueva);
    _activaId = nueva.id;
    notifyListeners();
    return nueva;
  }
}
