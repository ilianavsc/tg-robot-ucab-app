import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'catalogo_pistas.dart';

/// Etapas del escaneo de nueva pista alineado con el Gemelo Digital (`P05`):
/// 1. **Escaneo lento**: verifica la distancia estimada y captura inicial de sensores.
/// 2. **Recorrido normal**: revalida sensores y fija 3 puntos de control equitativos (`L / 3`).
/// 3. **Lecturas por segmento**: 3 lecturas de cada segmento entre puntos de control.
enum EtapaEscaneo {
  lecturaLenta(
    'Escaneo lento',
    'Verifica distancia de la pista y captura inicial de sensores',
  ),
  pasadaNormal(
    'Recorrido normal',
    'Revalida sensores y fija 3 puntos de control equitativos (L/3)',
  ),
  viaje1('Segmento 1 · 3 lecturas', '3 lecturas entre Inicio y PC1 (1/3)'),
  viaje2('Segmento 2 · 3 lecturas', '3 lecturas entre PC1 y PC2 (2/3)'),
  viaje3('Segmento 3 · 3 lecturas', '3 lecturas entre PC2 y PC3 (3/3)'),
  completado('Completado', 'Pista configurada');

  const EtapaEscaneo(this.titulo, this.detalle);

  final String titulo;
  final String detalle;

  bool get esViaje =>
      this == EtapaEscaneo.viaje1 ||
      this == EtapaEscaneo.viaje2 ||
      this == EtapaEscaneo.viaje3;

  /// Segmento (0, 1 o 2) que verifica la etapa actual.
  int? get segmento => switch (this) {
    EtapaEscaneo.viaje1 => 0,
    EtapaEscaneo.viaje2 => 1,
    EtapaEscaneo.viaje3 => 2,
    _ => null,
  };
}

/// Escaneo de una pista nueva (**simulación SIL**, determinista: sin `Random`
/// ni reloj). Se avanza con [avanzar] en segundos de simulación.
///
/// 1. **Escaneo lento** (0,20 m/s): verifica la distancia real por odometría
///    (encoders 11 PPR × 1:21,3, ruedas 65 mm) y captura los primeros datos de
///    sensores (4× TCRT5000, MPU-6050 y HC-SR04P frontal).
/// 2. **Recorrido a velocidad normal** (0,41 m/s): vuelve a verificar los
///    sensores y obtiene la primera muestra de ubicación de los **3 puntos de
///    control equitativos** (`L/3`, `2·L/3`, `L`, igual que en `P05`).
/// 3. **Lecturas por segmento**: realiza **3 lecturas** de cada uno de los 3
///    segmentos (9 lecturas totales) para validar y consolidar la ruta.
class EscaneoPista extends ChangeNotifier {
  EscaneoPista({
    required this.pistaId,
    required this.largoEstimadoM,
    this.geometria = TipoGeometriaPista.circuitoCerrado,
  });

  final String pistaId;

  /// Largo estimado al crear la pista: es el recorrido real de la simulación.
  final double largoEstimadoM;

  /// Geometría de la pista elegida al crearla (`circuitoCerrado` o `lineal`).
  final TipoGeometriaPista geometria;

  static const double velocidadLentaMs = 0.20;
  static const double velocidadNormalMs = 0.41;
  static const int lecturasRequeridasPorSegmento = 3;

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
  final List<int> _lecturasSegmento = <int>[0, 0, 0];
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
  List<int> get lecturasSegmento => List<int>.unmodifiable(_lecturasSegmento);
  List<double> get tiemposViajeS => List<double>.unmodifiable(_tiemposViaje);

  /// `true` cuando el largo medido en el escaneo lento coincide con el estimado.
  bool get distanciaVerificada =>
      _largoMedidoM != null && (_largoMedidoM! - largoEstimadoM).abs() <= 0.15;

  /// Número de lectura en curso (`1..3`) dentro del segmento activo, o `0`.
  int get lecturaActualEnSegmento {
    if (!_etapa.esViaje) return 0;
    return math.min(
      lecturasRequeridasPorSegmento,
      (progresoEtapa * lecturasRequeridasPorSegmento).floor() + 1,
    );
  }

  /// Total de lecturas de segmento completadas (`0..9`).
  int get totalLecturasCompletadas =>
      _lecturasSegmento.fold<int>(0, (int a, int b) => a + b);

  /// Largo de trabajo: el medido si ya existe, si no el estimado.
  double get largoM => _largoMedidoM ?? largoEstimadoM;

  /// Inicio y fin (m) del recorrido de la etapa actual.
  (double, double) get tramoActual {
    final double l = largoM;
    final List<double> pc = _puntosControl.isEmpty
        ? puntosControlEquitativos(l)
        : _puntosControl;
    return switch (_etapa) {
      EtapaEscaneo.viaje1 => (0, pc[0]),
      EtapaEscaneo.viaje2 => (pc[0], pc[1]),
      EtapaEscaneo.viaje3 => (pc[1], l),
      _ => (0, l),
    };
  }

  double get _velocidad => _etapa == EtapaEscaneo.lecturaLenta
      ? velocidadLentaMs
      : velocidadNormalMs;

  /// Duración (s de simulación) de la etapa actual.
  /// En las etapas de segmento se ejecutan 3 lecturas consecutivas del tramo.
  double get duracionEtapaS {
    if (completado) return 0;
    final (double a, double b) = tramoActual;
    final double base = (b - a) / _velocidad;
    return _etapa.esViaje ? base * lecturasRequeridasPorSegmento : base;
  }

  /// Avance de la etapa actual (0..1).
  double get progresoEtapa =>
      completado ? 1 : (_t / duracionEtapaS).clamp(0.0, 1.0);

  /// Posición del robot sobre la pista (m desde el inicio).
  double get posicionM {
    if (completado) return largoM;
    final (double a, double b) = tramoActual;
    if (_etapa.esViaje) {
      final double fase = progresoEtapa * lecturasRequeridasPorSegmento;
      final double local = (fase - fase.floor()).clamp(0.0, 1.0);
      // En pista lineal la segunda lectura regresa para evitar saltos visuales.
      final bool regreso =
          geometria == TipoGeometriaPista.lineal && fase.floor() == 1;
      return regreso ? b - (b - a) * local : a + (b - a) * local;
    }
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
        _actualizarLecturasParciales();
      } else {
        _t = duracionEtapaS;
        _tTotal += falta;
        resto -= falta;
        _cerrarEtapa();
      }
    }
    notifyListeners();
  }

  void _actualizarLecturasParciales() {
    final int? seg = _etapa.segmento;
    if (seg == null) return;
    final int hechas = (progresoEtapa * lecturasRequeridasPorSegmento)
        .floor()
        .clamp(0, lecturasRequeridasPorSegmento - 1);
    if (hechas > _lecturasSegmento[seg]) {
      _lecturasSegmento[seg] = hechas;
    }
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
        // 3 puntos de control equitativos (tercios del largo total, igual que P05)
        _puntosControl = puntosControlEquitativos(largoM);
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
        _lecturasSegmento[s] = lecturasRequeridasPorSegmento;
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
      lecturasPorSegmento: List<int>.of(_lecturasSegmento),
      frenteMinimoCm: _frenteMinimoCm,
      frenteMedioCm: _frenteMedioCm,
      firmaParedesCm: List<double>.of(_firma),
      giroTotalGrados: geometria == TipoGeometriaPista.lineal ? 0 : 360,
    );
  }
}
