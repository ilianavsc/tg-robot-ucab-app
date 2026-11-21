import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'catalogo_pistas.dart';

/// Etapas del escaneo básico del Gemelo Digital (adaptado de SIM2, sin torres
/// de control, BLE ni pruebas sin cinta).
enum EtapaEscaneo {
  lecturaLenta(
    'Lectura lenta',
    'Vuelta lenta: largo, perfil de radar y navegación base',
  ),
  pasadaNormal(
    'Pasada normal',
    'Fija PC1, PC2 y PC3 y la firma de paredes del radar',
  ),
  viaje1('Viaje 1/3', 'Verifica el segmento 1 (Inicio → PC1)'),
  viaje2('Viaje 2/3', 'Verifica el segmento 2 (PC1 → PC2)'),
  viaje3('Viaje 3/3', 'Verifica el segmento 3 (PC2 → PC3 / cierre)'),
  completado('Completado', 'Pista configurada');

  const EtapaEscaneo(this.titulo, this.detalle);

  final String titulo;
  final String detalle;

  bool get esViaje =>
      this == EtapaEscaneo.viaje1 ||
      this == EtapaEscaneo.viaje2 ||
      this == EtapaEscaneo.viaje3;

  /// Segmento (0, 1 o 2) que verifica un viaje.
  int? get segmento => switch (this) {
    EtapaEscaneo.viaje1 => 0,
    EtapaEscaneo.viaje2 => 1,
    EtapaEscaneo.viaje3 => 2,
    _ => null,
  };
}

/// Escaneo básico de una pista nueva (**simulación SIL**, determinista: sin
/// `Random` ni reloj). Se avanza con [avanzar] en segundos de simulación.
///
/// 1. **Lectura lenta** (0,20 m/s): mide el largo con la odometría
///    (encoders de 11 PPR × 1:21,3, ruedas de 65 mm), el perfil inicial del
///    HC-SR04P frontal y la navegación base (4× TCRT5000 + MPU-6050).
/// 2. **Pasada normal** (0,41 m/s, crucero de SIM1): fija PC1–PC3 en los
///    tercios de la pista y la firma de paredes del radar por segmento.
/// 3. **3 viajes de verificación** sin obstáculos, uno por segmento.
///
/// Al terminar, [metricas] trae todo lo necesario para que
/// [CatalogoPistas.completarEscaneo] marque la pista como configurada.
class EscaneoPista extends ChangeNotifier {
  EscaneoPista({required this.pistaId, required this.largoEstimadoM});

  final String pistaId;

  /// Largo estimado al crear la pista: es el recorrido real de la simulación.
  final double largoEstimadoM;

  static const double velocidadLentaMs = 0.20;
  static const double velocidadNormalMs = 0.41;

  /// Cuentas del encoder por vuelta de rueda (11 PPR × 1:21,3 × 4 flancos).
  static const double cuentasPorVuelta = 11 * 21.3 * 4;
  static const double diametroRuedaM = 0.065;

  EtapaEscaneo _etapa = EtapaEscaneo.lecturaLenta;
  double _t = 0; // segundos dentro de la etapa
  double _tTotal = 0;

  double? _largoMedidoM;
  int? _cuentasOdometria;
  double? _frenteMinimoCm;
  double? _frenteMedioCm;
  List<double> _puntosControl = const <double>[];
  List<double> _firma = const <double>[];
  final List<bool> _segmentos = <bool>[false, false, false];
  final List<double> _tiemposViaje = <double>[0, 0, 0];

  EtapaEscaneo get etapa => _etapa;
  bool get completado => _etapa == EtapaEscaneo.completado;
  double get tiempoTotalS => _tTotal;
  double? get largoMedidoM => _largoMedidoM;
  int? get cuentasOdometria => _cuentasOdometria;
  double? get frenteMinimoCm => _frenteMinimoCm;
  double? get frenteMedioCm => _frenteMedioCm;
  List<double> get puntosControlM => List<double>.unmodifiable(_puntosControl);
  List<double> get firmaParedesCm => List<double>.unmodifiable(_firma);
  List<bool> get segmentosValidados => List<bool>.unmodifiable(_segmentos);
  List<double> get tiemposViajeS => List<double>.unmodifiable(_tiemposViaje);

  /// Largo de trabajo: el medido si ya existe, si no el estimado.
  double get largoM => _largoMedidoM ?? largoEstimadoM;

  /// Inicio y fin (m) del recorrido de la etapa actual.
  (double, double) get tramoActual {
    final double l = largoM;
    final List<double> pc = _puntosControl.isEmpty
        ? puntosControlPara(l)
        : _puntosControl;
    return switch (_etapa) {
      EtapaEscaneo.viaje1 => (0, pc[0]),
      EtapaEscaneo.viaje2 => (pc[0], pc[1]),
      EtapaEscaneo.viaje3 => (pc[1], pc[2]),
      _ => (0, l),
    };
  }

  double get _velocidad => _etapa == EtapaEscaneo.lecturaLenta
      ? velocidadLentaMs
      : velocidadNormalMs;

  /// Duración (s de simulación) de la etapa actual.
  double get duracionEtapaS {
    if (completado) return 0;
    final (double a, double b) = tramoActual;
    return (b - a) / _velocidad;
  }

  /// Avance de la etapa actual (0..1).
  double get progresoEtapa =>
      completado ? 1 : (_t / duracionEtapaS).clamp(0.0, 1.0);

  /// Posición del robot sobre la pista (m desde el inicio).
  double get posicionM {
    if (completado) return largoM;
    final (double a, double b) = tramoActual;
    return a + (b - a) * progresoEtapa;
  }

  /// Velocidad actual del robot (m/s).
  double get velocidadMs => completado ? 0 : _velocidad;

  /// Avance global del escaneo (0..1), por etapas iguales.
  double get progresoTotal {
    if (completado) return 1;
    return (_etapa.index + progresoEtapa) / EtapaEscaneo.completado.index;
  }

  /// Avanza [dt] segundos de simulación (puede cruzar varias etapas).
  void avanzar(double dt) {
    if (completado || dt <= 0) return;
    double resto = dt;
    while (resto > 0 && !completado) {
      final double falta = duracionEtapaS - _t;
      if (resto < falta) {
        _t += resto;
        _tTotal += resto;
        resto = 0;
      } else {
        _t = duracionEtapaS;
        _tTotal += falta;
        resto -= falta;
        _cerrarEtapa();
      }
    }
    notifyListeners();
  }

  /// Completa todo el escaneo de una vez (pruebas y Modo Demo).
  void completarTodo() {
    while (!completado) {
      avanzar(duracionEtapaS - _t + 1e-9);
    }
  }

  void _cerrarEtapa() {
    switch (_etapa) {
      case EtapaEscaneo.lecturaLenta:
        // Odometría: cuentas enteras del encoder → metros (cuantización real)
        final double vuelta = math.pi * diametroRuedaM;
        _cuentasOdometria = (largoEstimadoM / vuelta * cuentasPorVuelta)
            .round();
        _largoMedidoM = double.parse(
          (_cuentasOdometria! / cuentasPorVuelta * vuelta).toStringAsFixed(3),
        );
        // Perfil inicial del radar frontal en la vuelta lenta (simulado)
        _frenteMinimoCm = 62;
        _frenteMedioCm = 148;
      case EtapaEscaneo.pasadaNormal:
        _puntosControl = puntosControlPara(largoM);
        // Firma de paredes del radar delantero por segmento (simulada)
        _firma = <double>[
          for (int i = 0; i < 3; i++)
            double.parse(
              (135 + 12 * math.sin(i * 1.7 + largoM)).toStringAsFixed(1),
            ),
        ];
      case EtapaEscaneo.viaje1:
      case EtapaEscaneo.viaje2:
      case EtapaEscaneo.viaje3:
        final int s = _etapa.segmento!;
        _segmentos[s] = true;
        _tiemposViaje[s] = double.parse(duracionEtapaS.toStringAsFixed(1));
      case EtapaEscaneo.completado:
        return;
    }
    _etapa = EtapaEscaneo.values[_etapa.index + 1];
    _t = 0;
  }

  /// Métricas para el catálogo (solo cuando el escaneo terminó).
  MetricasPista? get metricas {
    if (!completado) return null;
    return MetricasPista(
      largoM: largoM,
      puntosControlM: List<double>.of(_puntosControl),
      segmentosValidados: List<bool>.of(_segmentos),
      frenteMinimoCm: _frenteMinimoCm,
      frenteMedioCm: _frenteMedioCm,
      firmaParedesCm: List<double>.of(_firma),
    );
  }
}
