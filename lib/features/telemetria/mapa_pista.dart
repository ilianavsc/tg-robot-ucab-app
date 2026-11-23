import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/demo/simulacion_pista.dart';
import '../../core/models/estado.dart';
import '../../core/models/ultrasonido.dart';
import '../../core/mqtt/mqtt_service.dart';
import '../../core/pistas/trazado_pista.dart';
import '../../core/theme/cockpit_theme.dart';
import '../auth/catalogo_pistas.dart';
import '../perfil/aprendizaje_ruta.dart';
import 'cockpit_datos.dart';
import 'cockpit_ui.dart';

/// Estado visual instantáneo del indicador del robot en el mapa (paridad P04).
enum EstadoVisualRobot {
  enMovimiento,
  detenido,
  obstaculo,
  frenado,
  completado,
}

/// Geometría del circuito para un lienzo dado. Dibuja el **trazado real**
/// de la pista ([TrazadoPista]: la canónica de 9,0 m de SIM1/SIM2 por
/// defecto, o el circuito histórico de 8,05 m de la Pista A, o la pista lineal
/// en Modo Demo) con su forma exacta, centrado y a escala.
class PistaGeometria {
  PistaGeometria(this.tamano, [TrazadoPista? trazado])
    : trazado = trazado ?? TrazadoPista.canonica() {
    final double lado = math.min(tamano.width, tamano.height);
    if (!this.trazado.cerrada) {
      final double margenX = math.max(38, tamano.width * 0.09);
      const double margenArriba = 52;
      const double margenAbajo = 56;
      area = Rect.fromLTRB(
        margenX,
        margenArriba,
        math.max(margenX + 40, tamano.width - margenX),
        math.max(margenArriba + 40, tamano.height - margenAbajo),
      );
    } else {
      final double margenX = math.max(28, tamano.width * 0.11);
      final double margenArriba = math.max(58, tamano.height * 0.17);
      final double margenAbajo = math.max(44, tamano.height * 0.14);
      area = Rect.fromLTRB(
        margenX,
        margenArriba,
        tamano.width - margenX,
        tamano.height - margenAbajo,
      );
    }
    camino = caminoEnLienzo(this.trazado, area);
    _metrica = camino.computeMetrics().first;
    escala = lado;
  }

  /// Pista que se dibuja.
  final TrazadoPista trazado;

  /// Zona del lienzo donde cabe el circuito.
  late final Rect area;

  final Size tamano;
  late final Path camino;
  late final PathMetric _metrica;

  /// Recorrido medible del circuito (para extraer tramos).
  PathMetric get metrica => _metrica;

  /// Lado menor del lienzo (px): sirve para escalar trazos y textos.
  late final double escala;

  double get longitud => _metrica.length;

  Tangent _en(double fraccion) {
    final double f = trazado.cerrada
        ? fraccion - fraccion.floorToDouble()
        : fraccion.clamp(0.0, 1.0);
    return _metrica.getTangentForOffset(f * _metrica.length)!;
  }

  /// Punto del circuito en la fracción [fraccion] (0..1, 0 = Cuarto de Componentes).
  Offset puntoEn(double fraccion) => _en(fraccion).position;

  /// Ángulo (rad) de avance en esa fracción.
  double anguloEn(double fraccion) => _en(fraccion).angle;
}

/// Fracción del circuito de cada nodo: Cuarto de Componentes en la salida,
/// Punto de Control en PC1 (3,0 / 9,0) y Laboratorio 1 en PC3 (7,5 / 9,0).
/// Es la misma en cualquier pista porque sus estaciones escalan con el largo.
double fraccionDeDestino(DestinoPista d) =>
    SimulacionPista.posicionesPara(largoCanonicoM)[d]! / largoCanonicoM;

/// Fracción de PC2 (fin del tramo sin línea, 4,5 / 9,0).
double get fraccionPc2 => puntosControlCanonicosM[1] / largoCanonicoM;

/// Separación (px) entre el trazado y la etiqueta de una estación. En la
/// canónica (recta y estrecha) deja libre el barrido del cono del ultrasonido
/// en las horquillas; en la Pista A (curvas y una S) va pegada al nodo.
double _separacionEtiqueta(PistaGeometria g) =>
    g.trazado.id == 'A' ? 18 : 52;

Color colorDeZona(ZonaSonar z) {
  switch (z) {
    case ZonaSonar.libre:
      return CockpitColors.ok;
    case ZonaSonar.precaucion:
      return CockpitColors.warning;
    case ZonaSonar.parada:
      return CockpitColors.hazard;
    case ZonaSonar.fallo:
    case ZonaSonar.sinSenal:
    case ZonaSonar.sinDatos:
      return CockpitColors.outline;
  }
}

/// Parte del circuito que va de [desde] a [hasta] (fracciones 0..1) siguiendo
/// el sentido de marcha; si [hasta] < [desde] da la vuelta por la base.
Path tramoDelCircuito(PathMetric m, double desde, double hasta) {
  final double l = m.length;
  double f(double x) => x - x.floorToDouble();
  final double d = f(desde) * l;
  final double h = f(hasta) * l;
  if (h >= d) return m.extractPath(d, h);
  return m.extractPath(d, l)..addPath(m.extractPath(0, h), Offset.zero);
}

/// Rectángulo de la etiqueta de un nodo (con su "píldora" de fondo): se
/// coloca hacia fuera del lazo, perpendicular al trazado.
Rect rectEtiquetaNodo(PistaGeometria g, DestinoPista d) {
  final double f = fraccionDeDestino(d);
  final Offset p = g.puntoEn(f);
  final TextPainter tp = _textoEtiqueta(d, false)..layout();
  const double rx = 5, ry = 3;
  final double ancho = tp.width + 2 * rx;
  final double alto = tp.height + 2 * ry;
  final double ang = g.anguloEn(f);
  Offset n = Offset(-math.sin(ang), math.cos(ang));
  if ((p - g.area.center).dx * n.dx + (p - g.area.center).dy * n.dy < 0) {
    n = -n;
  }
  final double sep = _separacionEtiqueta(g);
  double x;
  double y;
  // A un lado del nodo solo si cabe en el lienzo; si no, arriba o abajo.
  final double xLado = n.dx < 0 ? p.dx - sep - ancho : p.dx + sep;
  final bool cabeAlLado =
      xLado >= 4 && xLado + ancho <= g.tamano.width - 4;
  if (n.dy.abs() >= n.dx.abs() || !cabeAlLado) {
    // Arriba o abajo del trazado, extendida hacia el extremo más cercano del
    // lazo: dos estaciones en la misma recta no se pisan.
    x = p.dx >= g.area.center.dx ? p.dx - 12 : p.dx + 12 - ancho;
    y = n.dy < 0 ? p.dy - sep - alto : p.dy + sep;
  } else {
    x = xLado;
    y = p.dy - alto / 2;
  }
  x = x.clamp(4.0, math.max(4.0, g.tamano.width - ancho - 4));
  y = y.clamp(4.0, math.max(4.0, g.tamano.height - alto - 4));
  return Rect.fromLTWH(x, y, ancho, alto);
}

TextPainter _textoEtiqueta(DestinoPista d, bool activo) => TextPainter(
  text: TextSpan(
    text: d.etiquetaMapa,
    style: mono(
      size: 10.5,
      peso: FontWeight.w600,
      color: activo ? CockpitColors.primary : CockpitColors.onSurface,
      espaciado: 0.3,
      altura: 1.25,
    ),
  ),
  textAlign: TextAlign.center,
  textDirection: TextDirection.ltr,
);

/// Triángulo del cono del ultrasonido frontal con el robot en [p] mirando a
/// [ang]. El largo (28–58 px) crece con la lectura; la abertura es estrecha
/// para que no invada las etiquetas de las estaciones.
List<Offset> triangulosCono(Offset p, double ang, double frenteCm) {
  final double largo = 28 + (frenteCm.clamp(0.0, 150.0) / 150.0) * 30;
  const double abertura = 0.26;
  return <Offset>[
    p,
    p + Offset.fromDirection(ang - abertura, largo),
    p + Offset.fromDirection(ang + abertura, largo),
  ];
}

/// Dibuja el circuito, los 3 nodos, el robot con su flecha y el cono del
/// ultrasonido frontal. Con robot (Modo Demo) aplica el **borrado progresivo**:
/// el tramo ya recorrido se atenúa a una línea punteada muy tenue (*ghost
/// line*) y solo queda iluminado en turquesa el tramo pendiente hacia el
/// destino. Sin robot (`fraccionRobot == null`) pinta toda la pista iluminada.
class PintorPista extends CustomPainter {
  const PintorPista({
    required this.destino,
    this.fraccionRobot,
    this.fraccionInicioTramo,
    this.obstaculo,
    this.frenteCm,
    this.zona = ZonaSonar.sinDatos,
    this.puntosRuta = const <double>[],
    this.trazado,
    this.vueltaCompleta = false,
    this.vueltaCompletada = false,
    this.puntosControlM = const <double>[],
    this.mostrarCheckpointsP05 = false,
    this.estadoRobot = EstadoVisualRobot.enMovimiento,
  });

  /// Pista que se dibuja (`null` = canónica de 9,0 m).
  final TrazadoPista? trazado;
  final bool vueltaCompleta;
  final bool vueltaCompletada;

  /// Puntos de control equitativos (`L/3`, `2·L/3`, `L`) fijados en el escaneo.
  final List<double> puntosControlM;

  /// `true` en pistas nuevas escaneadas o lineales: dibuja `INICIO`, `PC1`,
  /// `PC2` y `PC3 / META` con cotas en metros y paridad visual con P04.
  final bool mostrarCheckpointsP05;

  /// Estado visual instantáneo del robot (movimiento, detenido, obstáculo, freno, completado).
  final EstadoVisualRobot estadoRobot;

  final DestinoPista destino;
  final double? fraccionRobot;

  /// Dónde empezó el tramo actual (fracción 0..1).
  final double? fraccionInicioTramo;
  final double? obstaculo;
  final double? frenteCm;
  final ZonaSonar zona;

  /// Puntos de control aprendidos por el Administrador (fracciones 0..1) que
  /// no coinciden con una estación: se dibujan como rombos pequeños.
  final List<double> puntosRuta;

  @override
  void paint(Canvas canvas, Size size) {
    final PistaGeometria g = PistaGeometria(size, trazado);

    // Retícula tenue de fondo
    final Paint rejilla = Paint()
      ..color = CockpitColors.outlineVariant.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), rejilla);
    }
    for (double y = 0; y <= size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rejilla);
    }

    final double? f = fraccionRobot;
    final bool esLineal = !g.trazado.cerrada;
    if (esLineal) {
      // Carril base de la pista lineal (tramo pendiente, estilo P04)
      canvas.drawPath(
        g.camino,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = CockpitColors.surfaceHigh.withValues(alpha: 0.72),
      );
      canvas.drawPath(
        g.camino,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..color = CockpitColors.outlineVariant.withValues(alpha: 0.75),
      );
      _punteadoPendiente(canvas, g.camino);
      // Tramo recorrido resaltado en acento #00F2FE (o esmeralda al completar)
      if (f != null && f > 0.001) {
        final double finPx = f.clamp(0.0, 1.0) * g.longitud;
        final Color colorRecorrido = estadoRobot == EstadoVisualRobot.completado
            ? CockpitColors.ok
            : CockpitColors.primary;
        _pistaIluminada(
          canvas,
          g.metrica.extractPath(0, finPx),
          color: colorRecorrido,
        );
      }
    } else if (f == null) {
      _pistaIluminada(canvas, g.camino);
    } else {
      // Huella del circuito: línea apenas visible
      canvas.drawPath(
        g.camino,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = CockpitColors.outlineVariant.withValues(alpha: 0.22),
      );
      final double ini = fraccionInicioTramo ?? f;
      final double fin = fraccionDeDestino(destino);
      // Ya recorrido: punteada muy tenue (borrado progresivo)
      if (vueltaCompleta && !vueltaCompletada && f < 0.002) {
        _pistaIluminada(canvas, g.camino);
      } else {
        _fantasma(canvas, tramoDelCircuito(g.metrica, ini, f));
        // Pendiente hacia el destino: iluminado en turquesa
        if (_distanciaAdelante(f, fin) > 0.002) {
          _pistaIluminada(canvas, tramoDelCircuito(g.metrica, f, fin));
        }
      }
    }

    // Obstáculo simulado
    final double? o = obstaculo;
    if (o != null) {
      final Offset p = g.puntoEn(o);
      canvas.drawCircle(
        p,
        13,
        Paint()..color = CockpitColors.hazard.withValues(alpha: 0.24),
      );
      canvas.drawCircle(p, 6, Paint()..color = CockpitColors.hazard);
    }

    // Puntos de control aprendidos (ruta guardada del Administrador)
    for (int i = 0; i < puntosRuta.length; i++) {
      _puntoControl(canvas, g.puntoEn(puntosRuta[i]), 'P${i + 1}');
    }

    if (mostrarCheckpointsP05 || esLineal) {
      final List<double> pcs = puntosControlM.length == 3
          ? puntosControlM
          : puntosControlEquitativos(g.trazado.largoM);
      final double l = g.trazado.largoM > 0 ? g.trazado.largoM : 1.0;
      final double fActual = f ?? -1.0;
      _marcadorCheckpoint(
        canvas,
        size,
        g.puntoEn(0),
        'INICIO',
        '0,0 m',
        alcanzado: fActual >= 0.0,
        esMeta: false,
      );
      for (int i = 0; i < pcs.length; i++) {
        final double frac = (pcs[i] / l).clamp(0.0, 1.0);
        final bool esMeta = i == pcs.length - 1;
        final String etiqueta = esMeta ? 'PC3 / META' : 'PC${i + 1}';
        _marcadorCheckpoint(
          canvas,
          size,
          g.puntoEn(frac),
          etiqueta,
          '${metrosPista(pcs[i])} m',
          alcanzado: fActual >= frac - 0.005,
          esMeta: esMeta,
        );
      }
      if (f != null) {
        final Offset p = g.puntoEn(f);
        final double ang = g.anguloEn(f);
        _cono(canvas, g, p, ang, lineal: esLineal);
        _robot(canvas, p, ang);
      }
      return;
    }

    // PC2 de la especificación (PC1 y PC3 son el Punto de Control y el
    // Laboratorio 1)
    _puntoControl(canvas, g.puntoEn(fraccionPc2), 'PC2', arriba: true);

    // Nodos
    for (final DestinoPista d in DestinoPista.values) {
      _nodo(canvas, g, d);
    }

    // Cono del ultrasonido y robot
    if (f != null) {
      final Offset p = g.puntoEn(f);
      final double ang = g.anguloEn(f);
      _cono(canvas, g, p, ang);
      _robot(canvas, p, ang);
    }

    // Etiquetas de las estaciones al final: siempre legibles sobre el cono
    for (final DestinoPista d in DestinoPista.values) {
      _etiqueta(canvas, g, d);
    }
  }

  static double _distanciaAdelante(double desde, double hasta) {
    final double d = hasta - desde;
    return d - d.floorToDouble();
  }

  void _punteadoPendiente(Canvas canvas, Path camino) {
    final Paint pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = CockpitColors.onSurfaceVariant.withValues(alpha: 0.28);
    for (final PathMetric m in camino.computeMetrics()) {
      for (double d = 0; d < m.length; d += 14) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), pincel);
      }
    }
  }

  void _pistaIluminada(
    Canvas canvas,
    Path camino, {
    Color color = CockpitColors.primary,
  }) {
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = color.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = color.withValues(alpha: 0.30),
    );
    canvas.drawPath(
      camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _marcadorCheckpoint(
    Canvas canvas,
    Size size,
    Offset p,
    String etiqueta,
    String cotaM, {
    required bool alcanzado,
    required bool esMeta,
  }) {
    final Color colorNodo = esMeta
        ? (alcanzado ? CockpitColors.ok : CockpitColors.secondary)
        : (alcanzado ? CockpitColors.primary : CockpitColors.outline);
    if (alcanzado) {
      canvas.drawCircle(
        p,
        12,
        Paint()..color = colorNodo.withValues(alpha: 0.22),
      );
    }
    final Path rombo = Path()
      ..moveTo(p.dx, p.dy - 7.5)
      ..lineTo(p.dx + 7.5, p.dy)
      ..lineTo(p.dx, p.dy + 7.5)
      ..lineTo(p.dx - 7.5, p.dy)
      ..close();
    canvas.drawPath(
      rombo,
      Paint()..color = alcanzado ? colorNodo : CockpitColors.surface,
    );
    canvas.drawPath(
      rombo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colorNodo,
    );

    final TextPainter tpTop = TextPainter(
      text: TextSpan(
        text: etiqueta,
        style: CockpitText.telemetrySm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: alcanzado ? colorNodo : CockpitColors.onSurface,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double xTop = (p.dx - tpTop.width / 2).clamp(
      6.0,
      math.max(6.0, size.width - tpTop.width - 6.0),
    );
    tpTop.paint(canvas, Offset(xTop, p.dy - 14 - tpTop.height));

    final TextPainter tpCota = TextPainter(
      text: TextSpan(
        text: cotaM,
        style: CockpitText.telemetrySm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: CockpitColors.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double xCota = (p.dx - tpCota.width / 2).clamp(
      6.0,
      math.max(6.0, size.width - tpCota.width - 6.0),
    );
    tpCota.paint(canvas, Offset(xCota, p.dy + 13));
  }

  /// Tramo recorrido: puntos y rayas muy tenues, sin resplandor.
  void _fantasma(Canvas canvas, Path tramo) {
    final Paint pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = CockpitColors.primary.withValues(alpha: 0.16);
    for (final PathMetric m in tramo.computeMetrics()) {
      for (double d = 0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), pincel);
      }
    }
  }

  void _puntoControl(
    Canvas canvas,
    Offset p,
    String texto, {
    bool arriba = false,
  }) {
    final Path rombo = Path()
      ..moveTo(p.dx, p.dy - 7)
      ..lineTo(p.dx + 7, p.dy)
      ..lineTo(p.dx, p.dy + 7)
      ..lineTo(p.dx - 7, p.dy)
      ..close();
    canvas.drawPath(rombo, Paint()..color = CockpitColors.surface);
    canvas.drawPath(
      rombo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = CockpitColors.secondary,
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: mono(
          size: 9,
          peso: FontWeight.w700,
          color: CockpitColors.secondary,
          espaciado: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p + Offset(-tp.width / 2, arriba ? -9 - tp.height : 9));
  }

  void _nodo(Canvas canvas, PistaGeometria g, DestinoPista d) {
    final Offset p = g.puntoEn(fraccionDeDestino(d));
    final bool activo = d == destino;
    final Color color = d == DestinoPista.cuartoComponentes
        ? CockpitColors.ok
        : (d == DestinoPista.puntoControl
              ? CockpitColors.primary
              : CockpitColors.secondary);
    if (activo) {
      canvas.drawCircle(
        p,
        17,
        Paint()
          ..color = CockpitColors.primary.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawCircle(p, 13, Paint()..color = CockpitColors.surface);
    canvas.drawCircle(
      p,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = activo ? 3 : 2
        ..color = activo ? CockpitColors.primary : color.withValues(alpha: 0.7),
    );
    canvas.drawCircle(p, 5, Paint()..color = color);
  }

  void _etiqueta(Canvas canvas, PistaGeometria g, DestinoPista d) {
    final Rect r = rectEtiquetaNodo(g, d);
    final bool activo = d == destino;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(5)),
      Paint()..color = CockpitColors.surface.withValues(alpha: 0.88),
    );
    final TextPainter tp = _textoEtiqueta(d, activo)..layout();
    tp.paint(canvas, Offset(r.left + 5, r.top + 3));
  }

  void _cono(
    Canvas canvas,
    PistaGeometria g,
    Offset p,
    double ang, {
    bool lineal = false,
  }) {
    final double? d = frenteCm;
    if (d == null || zona == ZonaSonar.fallo || zona == ZonaSonar.sinDatos) {
      return;
    }
    final Color c = colorDeZona(zona);
    final bool alertaCercana =
        zona == ZonaSonar.precaucion || zona == ZonaSonar.parada;
    final List<Offset> v = triangulosCono(
      p,
      ang,
      lineal ? math.min(d, 90) : d,
    );
    final Path cono = Path()
      ..moveTo(v[0].dx, v[0].dy)
      ..lineTo(v[1].dx, v[1].dy)
      ..lineTo(v[2].dx, v[2].dy)
      ..close();
    canvas.drawPath(
      cono,
      Paint()..color = c.withValues(alpha: alertaCercana ? 0.34 : 0.18),
    );
    canvas.drawPath(
      cono,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = alertaCercana ? 1.5 : 1.0
        ..color = c.withValues(alpha: alertaCercana ? 0.85 : 0.55),
    );
    if (lineal && !alertaCercana) {
      return;
    }
    // Lectura en cm: a un lado o al otro de la punta, donde no pise ninguna
    // etiqueta de estación.
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${d.toStringAsFixed(0)} cm',
        style: CockpitText.telemetrySm.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: c,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Offset punta = (v[1] + v[2]) / 2;
    if (lineal) {
      final double lx = (punta.dx - tp.width / 2).clamp(
        6.0,
        math.max(6.0, g.tamano.width - tp.width - 6.0),
      );
      tp.paint(canvas, Offset(lx, p.dy - 26 - tp.height));
      return;
    }
    final List<Rect> etiquetas = <Rect>[
      for (final DestinoPista n in DestinoPista.values) rectEtiquetaNodo(g, n),
    ];
    Rect candidato(double dy) => Rect.fromLTWH(
      (punta.dx - tp.width / 2).clamp(2.0, g.tamano.width - tp.width - 2),
      (punta.dy + dy).clamp(2.0, g.tamano.height - tp.height - 2),
      tp.width,
      tp.height,
    );
    Rect elegido = candidato(-tp.height - 8);
    if (etiquetas.any((Rect e) => e.overlaps(elegido))) {
      elegido = candidato(8);
    }
    tp.paint(canvas, elegido.topLeft);
  }

  Color _colorEstadoRobot() {
    switch (estadoRobot) {
      case EstadoVisualRobot.enMovimiento:
        return CockpitColors.primary;
      case EstadoVisualRobot.completado:
        return CockpitColors.ok;
      case EstadoVisualRobot.detenido:
        return CockpitColors.warning;
      case EstadoVisualRobot.obstaculo:
      case EstadoVisualRobot.frenado:
        return CockpitColors.hazard;
    }
  }

  void _robot(Canvas canvas, Offset p, double ang) {
    final Color acento = _colorEstadoRobot();
    final bool alerta =
        estadoRobot == EstadoVisualRobot.obstaculo ||
        estadoRobot == EstadoVisualRobot.frenado;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(ang);
    // Halo de estado (más intenso en alerta o movimiento activo)
    canvas.drawCircle(
      Offset.zero,
      alerta ? 21 : 17,
      Paint()
        ..color = acento.withValues(alpha: alerta ? 0.30 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Ruedas laterales estilo P04
    final Paint rueda = Paint()..color = CockpitColors.outline;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -13, 12, 3),
        const Radius.circular(1.5),
      ),
      rueda,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, 10, 12, 3),
        const Radius.circular(1.5),
      ),
      rueda,
    );
    // Chasis del robot
    final RRect cuerpo = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-15, -10, 30, 20),
      const Radius.circular(5),
    );
    canvas.drawRRect(cuerpo, Paint()..color = CockpitColors.surfaceLow);
    canvas.drawRRect(
      cuerpo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = acento,
    );
    // Flecha de orientación/rumbo (hacia +x)
    final Path flecha = Path()
      ..moveTo(9, 0)
      ..lineTo(-4, -6)
      ..lineTo(-1, 0)
      ..lineTo(-4, 6)
      ..close();
    canvas.drawPath(flecha, Paint()..color = acento);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PintorPista v) =>
      v.destino != destino ||
      v.fraccionRobot != fraccionRobot ||
      v.fraccionInicioTramo != fraccionInicioTramo ||
      v.obstaculo != obstaculo ||
      v.frenteCm != frenteCm ||
      v.zona != zona ||
      v.estadoRobot != estadoRobot ||
      v.trazado?.id != trazado?.id ||
      v.trazado?.largoM != trazado?.largoM ||
      v.trazado?.cerrada != trazado?.cerrada ||
      v.vueltaCompleta != vueltaCompleta ||
      v.vueltaCompletada != vueltaCompletada ||
      v.mostrarCheckpointsP05 != mostrarCheckpointsP05 ||
      !listEquals(v.puntosControlM, puntosControlM) ||
      !listEquals(v.puntosRuta, puntosRuta);
}

/// Texto de la seguridad frontal para la tarjeta de misión.
String textoSeguridad(ZonaSonar z) {
  switch (z) {
    case ZonaSonar.libre:
      return 'OK';
    case ZonaSonar.precaucion:
      return 'PRECAUCIÓN';
    case ZonaSonar.parada:
      return 'PARADA';
    case ZonaSonar.fallo:
      return 'FALLO SENSOR';
    case ZonaSonar.sinSenal:
      return 'SIN SEÑAL';
    case ZonaSonar.sinDatos:
      return '—';
  }
}

/// **Mapa de Pista** (vista principal del Dashboard): circuito con el robot,
/// el cono del ultrasonido frontal, tarjeta de misión, destinos y pausa.
///
/// En **Modo Demo** todo sale de la simulación física (`MqttService.pista`).
/// Con el robot real NO se inventa nada: el robot no tiene localización
/// absoluta (solo 4× TCRT5000 y 2× HC-SR04P), así que no se dibuja su posición
/// ni se ofrecen destinos; sí se muestran velocidad, batería y distancia
/// frontal reales, y Pausar/Reanudar envían `frenar` / `auto`.
///
/// Con [tecnico] en `false` (vista por defecto de Operador y Administrador sin
/// Modo Desarrollador) solo muestra el mapa de la pista activa y sus
/// estaciones: sin tarjeta de misión, destinos manuales ni pausa.
class TarjetaMapaPista extends StatelessWidget {
  const TarjetaMapaPista({super.key, this.tecnico = true});

  /// Muestra la misión, los destinos y la pausa (herramientas técnicas).
  final bool tecnico;

  @override
  Widget build(BuildContext context) {
    final MqttService servicio = context.watch<MqttService>();
    final SimulacionPista? sim = servicio.pista;
    final Estado? estado = servicio.ultimoEstado;
    final bool sinSenal = estadoSinSenal(estado);
    final Estado? e = sinSenal ? null : estado;
    final PistaLocal? activa = context.watch<CatalogoPistas?>()?.activa;
    final bool demo = sim != null;
    final double largo =
        sim?.longitudM ?? e?.largoM ?? activa?.longitudM ?? largoCanonicoM;
    // En Modo Demo la pista activa es siempre lineal (INICIO → PC3 / META) con paridad P04.
    final TipoGeometriaPista geometria = demo
        ? TipoGeometriaPista.lineal
        : (activa?.geometria ?? TipoGeometriaPista.circuitoCerrado);
    final TrazadoPista trazado = demo
        ? TrazadoPista.lineal(largo, id: 'DEMO')
        : TrazadoPista.paraPista(activa?.id, largo, geometria: geometria);
    final bool mostrarCheckpointsP05 =
        demo ||
        (activa != null &&
            (activa.esLineal ||
                (activa.id != 'A' && activa.esCircuitoCerrado)));
    final List<double> puntosControlM = demo
        ? puntosControlEquitativos(trazado.largoM)
        : (activa?.metricas?.puntosControlM ??
              puntosControlEquitativos(trazado.largoM));
    final Ultrasonido? us = servicio.ultimoUltrasonido;
    final double? frenteActualCm = sim != null ? sim.frenteCm : us?.frenteValido;
    final double? fraccionObjetivo = sim != null
        ? (sim.modoVueltaCompleta ? sim.progresoVuelta : sim.fraccion)
        : (e?.progresoM != null && trazado.largoM > 0
              ? (e!.progresoM! / trazado.largoM).clamp(0.0, 1.0)
              : null);
    final double? distanciaActualM = sim != null
        ? (sim.modoVueltaCompleta
              ? sim.progresoVuelta * sim.longitudM
              : sim.posicionM)
        : e?.progresoM?.clamp(0.0, trazado.largoM);
    final ClasificacionRadar? clasificacionRadar =
        (activa?.metricas != null &&
            activa!.metricas!.perfilesSeccion.isNotEmpty &&
            frenteActualCm != null)
        ? activa.metricas!.clasificarLecturaRadar(
            posicionM: distanciaActualM ?? 0.0,
            frenteCm: frenteActualCm,
          )
        : null;
    final int viajesAfinados = activa?.metricas?.viajesOperacion ?? 0;
    final ZonaSonar zona = zonaFrente(us);
    final ({EstadoVisualRobot visual, String etiqueta, Color color})
    estadoRobot = _resolverEstadoRobot(
      sim: sim,
      estado: e,
      zona: zona,
      ultimoComando: servicio.ultimoComando,
    );
    final enlace = _enlace(servicio);
    // Puntos de control de la ruta guardada (solo los que no son estación)
    final List<double> extras = <double>[
      for (final double f
          in context.watch<AprendizajeRuta?>()?.fraccionesControl ??
              const <double>[])
        if (!DestinoPista.values.any(
          (DestinoPista d) => (fraccionDeDestino(d) - f).abs() < 0.005,
        ))
          f,
    ];

    return CockpitCard(
      key: const Key('mapa-pista'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Cabecera(
            demo: demo,
            enlace: enlace,
            pista: demo
                ? 'Pista lineal · Demo'
                : (activa == null
                      ? 'Pista canónica'
                      : (mostrarCheckpointsP05
                            ? '${activa.nombre} · ${activa.geometria.etiqueta}'
                            : activa.nombre)),
          ),
          const SizedBox(height: 12),
          _Mapa(
            sim: sim,
            us: us,
            zona: zona,
            hayDatos: e != null,
            puntosRuta: extras,
            trazado: trazado,
            puntosControlM: puntosControlM,
            mostrarCheckpointsP05: mostrarCheckpointsP05,
            fraccionObjetivo: fraccionObjetivo,
            distanciaActualM: distanciaActualM,
            esDemo: demo,
            etiquetaModo: demo ? 'DEMO' : (tecnico ? 'MQTT' : 'EN VIVO'),
            estadoRobot: estadoRobot.visual,
            etiquetaEstadoRobot: estadoRobot.etiqueta,
            colorEstadoRobot: estadoRobot.color,
          ),
          const SizedBox(height: 8),
          Text(
            mostrarCheckpointsP05
                ? textoPuntosControlEquitativos(
                    trazado.largoM,
                    puntosControlM: puntosControlM,
                  )
                : textoEstaciones(trazado.largoM),
            key: const Key('mapa-estaciones'),
            textAlign: TextAlign.center,
            style: CockpitText.telemetrySm.copyWith(
              color: CockpitColors.onSurfaceVariant,
            ),
          ),
          if (clasificacionRadar != null || viajesAfinados > 0) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                if (clasificacionRadar != null)
                  StatusPill(
                    key: const Key('mapa-clasificacion-radar'),
                    texto: clasificacionRadar.etiqueta,
                    color: switch (clasificacionRadar) {
                      ClasificacionRadar.obstaculoNuevo => CockpitColors.hazard,
                      ClasificacionRadar.paredFija => CockpitColors.primary,
                      ClasificacionRadar.libre => CockpitColors.ok,
                    },
                  ),
                if (viajesAfinados > 0)
                  StatusPill(
                    key: const Key('mapa-viajes-afinados'),
                    texto:
                        'Afinado · $viajesAfinados ${viajesAfinados == 1 ? 'viaje' : 'viajes'}',
                    color: CockpitColors.ok,
                    punto: false,
                  ),
              ],
            ),
          ],
          if (tecnico) ...<Widget>[
            const SizedBox(height: 12),
            _TarjetaMision(sim: sim, estado: e, zona: zona),
            const SizedBox(height: 14),
            _SelectorDestino(servicio: servicio, sim: sim),
            const SizedBox(height: 12),
            _BotonPausa(servicio: servicio, sim: sim, estado: e),
            if (sim?.ultimoEvento != null) ...<Widget>[
              const SizedBox(height: 10),
              _UltimoEvento(evento: sim!.ultimoEvento!),
            ],
          ],
        ],
      ),
    );
  }

  ({EstadoVisualRobot visual, String etiqueta, Color color})
  _resolverEstadoRobot({
    required SimulacionPista? sim,
    required Estado? estado,
    required ZonaSonar zona,
    required String? ultimoComando,
  }) {
    if (sim != null) {
      if (sim.vueltaCompletada || sim.fase == FaseMision.enDestino) {
        return (
          visual: EstadoVisualRobot.completado,
          etiqueta: 'COMPLETADO',
          color: CockpitColors.ok,
        );
      }
      if (sim.fase == FaseMision.bloqueada || zona == ZonaSonar.parada) {
        return (
          visual: EstadoVisualRobot.obstaculo,
          etiqueta: 'OBSTÁCULO',
          color: CockpitColors.hazard,
        );
      }
      if (sim.fase == FaseMision.pausada) {
        final bool frenado = ultimoComando == 'frenar';
        return (
          visual: frenado
              ? EstadoVisualRobot.frenado
              : EstadoVisualRobot.detenido,
          etiqueta: frenado ? 'FRENADO' : 'DETENIDO',
          color: frenado ? CockpitColors.hazard : CockpitColors.warning,
        );
      }
      return (
        visual: EstadoVisualRobot.enMovimiento,
        etiqueta: sim.fase == FaseMision.manual ? 'MANUAL' : 'EN MARCHA',
        color: CockpitColors.primary,
      );
    }
    if (estado != null) {
      if (zona == ZonaSonar.parada || estado.parada == 'obstaculo_frente') {
        return (
          visual: EstadoVisualRobot.obstaculo,
          etiqueta: 'OBSTÁCULO',
          color: CockpitColors.hazard,
        );
      }
      if (estado.detenidoPorSeguridad || ultimoComando == 'frenar') {
        return (
          visual: EstadoVisualRobot.frenado,
          etiqueta: 'FRENADO',
          color: CockpitColors.hazard,
        );
      }
      if (estado.velocidadMedia.abs() > 0.02) {
        return (
          visual: EstadoVisualRobot.enMovimiento,
          etiqueta: 'EN MARCHA',
          color: CockpitColors.primary,
        );
      }
      return (
        visual: EstadoVisualRobot.detenido,
        etiqueta: 'DETENIDO',
        color: CockpitColors.warning,
      );
    }
    return (
      visual: EstadoVisualRobot.detenido,
      etiqueta: 'ESPERA',
      color: CockpitColors.outline,
    );
  }

  ({String texto, Color color}) _enlace(MqttService s) {
    if (s.simulando) {
      return (texto: 'Modo Demo', color: CockpitColors.secondary);
    }
    if (s.conectado) {
      return s.recibiendoDatos
          ? (texto: 'Online', color: CockpitColors.ok)
          : (texto: 'Sin datos', color: CockpitColors.warning);
    }
    return (texto: 'Sin enlace', color: CockpitColors.outline);
  }
}

/// Metros con coma decimal: `9,0`, `8,05`, `3,0`.
String metrosPista(double m) {
  final String t = (m * 100).round() % 10 == 0
      ? m.toStringAsFixed(1)
      : m.toStringAsFixed(2);
  return t.replaceAll('.', ',');
}

/// Estaciones de una pista de [largoM] metros (PC1–PC3 de
/// `specs/pista_canonica.json`, escalados si la pista no mide 9,0 m).
String textoEstaciones(double largoM) {
  final List<double> pc = puntosControlPara(largoM);
  return 'Cuarto 0,0 · PC1 ${metrosPista(pc[0])} · PC2 ${metrosPista(pc[1])} · '
      'PC3 / Lab. 1 ${metrosPista(pc[2])} · cierre ${metrosPista(largoM)} m';
}

/// Etiqueta de puntos de control equitativos (`L/3`, `2·L/3`, `L`) para pistas
/// escaneadas con el Gemelo Digital (`P05`), tanto lineales como cerradas.
String textoPuntosControlEquitativos(
  double largoM, {
  List<double>? puntosControlM,
}) {
  final List<double> pc =
      (puntosControlM != null && puntosControlM.length == 3)
      ? puntosControlM
      : puntosControlEquitativos(largoM);
  return 'Inicio 0,0 · PC1 ${metrosPista(pc[0])} · PC2 ${metrosPista(pc[1])} · '
      'PC3 ${metrosPista(pc[2])} m';
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.demo,
    required this.enlace,
    required this.pista,
  });

  final bool demo;
  final String pista;
  final ({String texto, Color color}) enlace;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: CockpitColors.surfaceContainer,
            borderRadius: BorderRadius.circular(CockpitRadius.lg),
          ),
          child: const Icon(
            Icons.smart_toy_outlined,
            color: CockpitColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'MAPA DE PISTA',
                style: CockpitText.labelMd.copyWith(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              Text(
                demo ? '$pista · simulado · AGV-01' : '$pista · AGV-01',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CockpitText.telemetrySm.copyWith(
                  color: CockpitColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(texto: enlace.texto, color: enlace.color),
      ],
    );
  }
}

class _Mapa extends StatefulWidget {
  const _Mapa({
    required this.sim,
    required this.us,
    required this.zona,
    required this.hayDatos,
    required this.puntosRuta,
    required this.trazado,
    required this.fraccionObjetivo,
    required this.distanciaActualM,
    required this.esDemo,
    required this.etiquetaModo,
    required this.estadoRobot,
    required this.etiquetaEstadoRobot,
    required this.colorEstadoRobot,
    this.puntosControlM = const <double>[],
    this.mostrarCheckpointsP05 = false,
  });

  final List<double> puntosRuta;
  final TrazadoPista trazado;
  final SimulacionPista? sim;
  final Ultrasonido? us;
  final ZonaSonar zona;
  final bool hayDatos;
  final List<double> puntosControlM;
  final bool mostrarCheckpointsP05;
  final double? fraccionObjetivo;
  final double? distanciaActualM;
  final bool esDemo;
  final String etiquetaModo;
  final EstadoVisualRobot estadoRobot;
  final String etiquetaEstadoRobot;
  final Color colorEstadoRobot;

  @override
  State<_Mapa> createState() => _MapaState();
}

class _MapaState extends State<_Mapa> with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;
  Animation<double>? _animacion;
  double? _fraccionActual;

  @override
  void initState() {
    super.initState();
    _fraccionActual = widget.fraccionObjetivo;
    _controlador = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (!mounted || _animacion == null) return;
        setState(() {
          _fraccionActual = _animacion!.value;
        });
      });
  }

  @override
  void didUpdateWidget(covariant _Mapa oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double? destino = widget.fraccionObjetivo;
    if (destino == null) {
      _controlador.stop();
      _animacion = null;
      _fraccionActual = null;
      return;
    }
    final double? previo = _fraccionActual;
    if (previo == null ||
        oldWidget.trazado.id != widget.trazado.id ||
        oldWidget.trazado.cerrada != widget.trazado.cerrada) {
      _controlador.stop();
      _animacion = null;
      _fraccionActual = destino;
      return;
    }
    final double delta = destino - previo;
    if (delta.abs() < 0.0005) return;

    // Salto de reinicio (vuelta a 0 en pista lineal o salto grande hacia atrás):
    // reposiciona limpio sin retroceder por toda la pista.
    if (!widget.trazado.cerrada && delta < -0.25) {
      _controlador.stop();
      _animacion = null;
      _fraccionActual = destino;
      return;
    }
    // En circuito cerrado, si cruza 1 → 0 evita rebobinar.
    if (widget.trazado.cerrada && delta.abs() > 0.5) {
      _controlador.stop();
      _animacion = null;
      _fraccionActual = destino;
      return;
    }

    _controlador.duration = Duration(
      milliseconds: widget.esDemo ? 240 : 420,
    );
    _animacion = Tween<double>(begin: previo, end: destino).animate(
      CurvedAnimation(parent: _controlador, curve: Curves.easeOutCubic),
    );
    _controlador.forward(from: 0);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  String _formatoMetrosDos(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final SimulacionPista? s = widget.sim;
    final Color cz = colorDeZona(widget.zona);
    final String textoUs = widget.zona == ZonaSonar.libre
        ? 'US LIBRE'
        : (widget.zona == ZonaSonar.precaucion
              ? 'US PRECAUCIÓN'
              : (widget.zona == ZonaSonar.parada
                    ? 'US PARADA'
                    : (widget.zona == ZonaSonar.fallo
                          ? 'US FALLO'
                          : (widget.zona == ZonaSonar.sinSenal
                                ? 'US SIN SEÑAL'
                                : 'US —'))));
    final double? fraccionPintada = _fraccionActual ?? widget.fraccionObjetivo;
    final double largoM = widget.trazado.largoM;
    final double? distAnimadaM = fraccionPintada != null
        ? (fraccionPintada.clamp(0.0, 1.0) * largoM)
        : widget.distanciaActualM;
    final int pctAvance = fraccionPintada == null
        ? 0
        : (fraccionPintada.clamp(0.0, 1.0) * 100).round();
    final String textoDistancia = distAnimadaM == null
        ? '— / ${metrosPista(largoM)} m'
        : '${_formatoMetrosDos(distAnimadaM)} / ${metrosPista(largoM)} m';

    return Semantics(
      label: fraccionPintada == null
          ? 'Mapa de pista sin posición del robot'
          : 'Mapa de pista: avance $pctAvance por ciento, '
                '${s != null ? 'frente a ${s.frenteCm.toStringAsFixed(0)} centímetros' : widget.etiquetaEstadoRobot}',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool esLineal = !widget.trazado.cerrada;
          final Rect caja = widget.trazado.caja;
          final double alto = esLineal
              ? (c.maxWidth < 460 ? 226.0 : 240.0)
              : math.min(
                  math.max(
                    c.maxWidth * 0.78 * caja.height / caja.width + 190,
                    270,
                  ),
                  math.min(c.maxWidth * 0.86, 330),
                );
          final Widget lienzo = Container(
            height: alto,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: CockpitColors.surfaceLowest,
              borderRadius: BorderRadius.circular(CockpitRadius.lg),
              border: Border.all(
                color: CockpitColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    key: const Key('mapa-pista-lienzo'),
                    painter: PintorPista(
                      destino: s?.destino ?? DestinoPista.puntoControl,
                      fraccionRobot: fraccionPintada,
                      fraccionInicioTramo: s?.fraccionInicioTramo,
                      obstaculo: s?.obstaculoFraccion,
                      frenteCm: s != null ? s.frenteCm : widget.us?.frenteValido,
                      zona: widget.zona,
                      puntosRuta: widget.puntosRuta,
                      trazado: widget.trazado,
                      vueltaCompleta: s?.modoVueltaCompleta ?? false,
                      vueltaCompletada: s?.vueltaCompletada ?? false,
                      puntosControlM: widget.puntosControlM,
                      mostrarCheckpointsP05: widget.mostrarCheckpointsP05,
                      estadoRobot: widget.estadoRobot,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _Chip(
                    texto: fraccionPintada == null
                        ? 'SIN POSICIÓN'
                        : '${widget.etiquetaModo} · ${metrosPista(largoM)} m',
                    color: widget.esDemo
                        ? CockpitColors.primary
                        : CockpitColors.ok,
                    icono: fraccionPintada == null
                        ? Icons.location_off_outlined
                        : Icons.route,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _Chip(texto: textoUs, color: cz, icono: Icons.sensors),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Container(
                    key: const Key('mapa-telemetria-barra'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: CockpitColors.surfaceLow.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(CockpitRadius.md),
                      border: Border.all(
                        color: CockpitColors.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              textoDistancia,
                              key: const Key('mapa-distancia'),
                              style: CockpitText.telemetrySm.copyWith(
                                color: CockpitColors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$pctAvance %',
                              key: const Key('mapa-porcentaje'),
                              style: CockpitText.telemetrySm.copyWith(
                                color: CockpitColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: widget.colorEstadoRobot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.etiquetaEstadoRobot,
                              key: const Key('mapa-estado-robot'),
                              style: CockpitText.telemetrySm.copyWith(
                                color: widget.colorEstadoRobot,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: CockpitColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  CockpitRadius.sm,
                                ),
                              ),
                              child: Text(
                                widget.etiquetaModo,
                                key: const Key('mapa-modo-badge'),
                                style: CockpitText.telemetrySm.copyWith(
                                  fontSize: 10,
                                  color: CockpitColors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          if (fraccionPintada != null) return lienzo;
          // Sin posición: la explicación va debajo del lienzo, sin tapar la
          // pista ni las etiquetas.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              lienzo,
              const SizedBox(height: 8),
              Text(
                'El robot solo mide la línea (4× IR) y la distancia (2× '
                'ultrasonido): no hay localización absoluta. El mapa se '
                'anima en el Modo Demo.',
                key: const Key('mapa-sin-posicion'),
                textAlign: TextAlign.center,
                style: CockpitText.bodySm.copyWith(
                  color: CockpitColors.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.color, required this.icono});

  final String texto;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: CockpitColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(CockpitRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            texto,
            style: CockpitText.labelMd.copyWith(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de misión: fase, seguridad y 3 lecturas.
class _TarjetaMision extends StatelessWidget {
  const _TarjetaMision({
    required this.sim,
    required this.estado,
    required this.zona,
  });

  final SimulacionPista? sim;
  final Estado? estado;
  final ZonaSonar zona;

  ({String texto, Color color}) _fase() {
    final SimulacionPista? s = sim;
    if (s != null) {
      switch (s.fase) {
        case FaseMision.enRuta:
          return (
            texto: 'EN RUTA → ${s.destino.nombre}',
            color: CockpitColors.primary,
          );
        case FaseMision.enDestino:
          return (texto: 'EN ${s.destino.nombre}', color: CockpitColors.ok);
        case FaseMision.pausada:
          return (texto: 'MISIÓN PAUSADA', color: CockpitColors.warning);
        case FaseMision.bloqueada:
          return (texto: 'DETENIDO · OBSTÁCULO', color: CockpitColors.hazard);
        case FaseMision.manual:
          return (texto: 'CONTROL MANUAL', color: CockpitColors.secondary);
      }
    }
    final Estado? e = estado;
    if (e == null) {
      return (texto: 'SIN TELEMETRÍA', color: CockpitColors.outline);
    }
    final ParadaInfo p = describirParada(e.parada);
    if (p.detenido) return (texto: p.corta, color: CockpitColors.hazard);
    return e.modo == 'autonomo'
        ? (texto: 'SEGUIMIENTO AUTÓNOMO', color: CockpitColors.primary)
        : (texto: 'CONTROL MANUAL', color: CockpitColors.secondary);
  }

  @override
  Widget build(BuildContext context) {
    final fase = _fase();
    final Estado? e = estado;
    final SimulacionPista? s = sim;
    final Color cs = colorDeZona(zona);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CockpitColors.surfaceContainer,
        borderRadius: BorderRadius.circular(CockpitRadius.lg),
        border: Border.all(
          color: CockpitColors.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: fase.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      fase.texto,
                      key: const Key('mision-fase'),
                      style: CockpitText.labelMd.copyWith(
                        fontSize: 13,
                        color: fase.color,
                      ),
                    ),
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'SEGURIDAD: ',
                      style: CockpitText.telemetrySm.copyWith(
                        color: CockpitColors.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: textoSeguridad(zona),
                      style: CockpitText.labelMd.copyWith(
                        fontSize: 11,
                        color: cs,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: CockpitCell(
                  key: const Key('mision-velocidad'),
                  etiqueta: 'Velocidad',
                  valor: e == null
                      ? '—'
                      : e.velocidadMedia.abs().toStringAsFixed(2),
                  unidad: 'm/s',
                  tamano: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitCell(
                  key: const Key('mision-bateria'),
                  etiqueta: 'Batería 3S',
                  valor: e == null ? '—' : '${e.bateria}',
                  unidad: e == null ? null : '%',
                  color: e == null
                      ? CockpitColors.onSurface
                      : (e.bateriaBaja
                            ? CockpitColors.warning
                            : CockpitColors.ok),
                  tamano: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CockpitCell(
                  key: const Key('mision-avance'),
                  etiqueta: 'Avance',
                  valor: s == null
                      ? '—'
                      : (s.progresoTramo * 100).toStringAsFixed(0),
                  unidad: s == null ? null : '% tramo',
                  color: CockpitColors.secondary,
                  tamano: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Selector de destino. Solo existe en el Modo Demo: el firmware no recibe
/// destinos, así que con el robot real los botones quedan deshabilitados.
class _SelectorDestino extends StatelessWidget {
  const _SelectorDestino({required this.servicio, required this.sim});

  final MqttService servicio;
  final SimulacionPista? sim;

  static const Map<DestinoPista, IconData> _iconos = <DestinoPista, IconData>{
    DestinoPista.cuartoComponentes: Icons.inventory_2_outlined,
    DestinoPista.puntoControl: Icons.flag_outlined,
    DestinoPista.laboratorio1: Icons.science_outlined,
  };

  static const Map<DestinoPista, String> _claves = <DestinoPista, String>{
    DestinoPista.cuartoComponentes: 'destino-cuarto',
    DestinoPista.puntoControl: 'destino-control',
    DestinoPista.laboratorio1: 'destino-lab1',
  };

  @override
  Widget build(BuildContext context) {
    final SimulacionPista? s = sim;
    final bool activo = s != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'PUNTO DE DESTINO',
                style: CockpitText.labelMd.copyWith(
                  color: CockpitColors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              s == null ? 'SOLO EN DEMO' : (s.autonomo ? 'AUTÓNOMO' : 'MANUAL'),
              style: CockpitText.labelMd.copyWith(
                fontSize: 11,
                color: s == null
                    ? CockpitColors.outline
                    : CockpitColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final DestinoPista d in DestinoPista.values) ...<Widget>[
              if (d != DestinoPista.cuartoComponentes) const SizedBox(width: 8),
              Expanded(
                child: _BotonDestino(
                  clave: Key(_claves[d]!),
                  texto: d.corto,
                  icono: _iconos[d]!,
                  seleccionado: activo && s.destino == d,
                  habilitado: activo,
                  alPulsar: () => servicio.elegirDestinoDemo(d),
                ),
              ),
            ],
          ],
        ),
        if (!activo)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'El robot no recibe destinos: el firmware solo entiende '
              'adelante, atrás, giros, frenar y auto.',
              style: CockpitText.bodySm.copyWith(color: CockpitColors.outline),
            ),
          ),
      ],
    );
  }
}

class _BotonDestino extends StatelessWidget {
  const _BotonDestino({
    required this.clave,
    required this.texto,
    required this.icono,
    required this.seleccionado,
    required this.habilitado,
    required this.alPulsar,
  });

  final Key clave;
  final String texto;
  final IconData icono;
  final bool seleccionado;
  final bool habilitado;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final Color fg = seleccionado
        ? CockpitColors.onPrimary
        : (habilitado ? CockpitColors.onSurface : CockpitColors.outline);
    return Semantics(
      button: true,
      selected: seleccionado,
      enabled: habilitado,
      label: 'Destino $texto',
      child: Material(
        color: seleccionado ? CockpitColors.primary : CockpitColors.surfaceHigh,
        borderRadius: BorderRadius.circular(CockpitRadius.md),
        child: InkWell(
          key: clave,
          borderRadius: BorderRadius.circular(CockpitRadius.md),
          onTap: habilitado ? alPulsar : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icono, size: 18, color: fg),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: CockpitText.labelMd.copyWith(
                      fontSize: 11,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pausar / Reanudar la misión: usa las órdenes reales `frenar` y `auto`
/// (QoS 1), igual que ALTO y AUTO NAV de Controles.
class _BotonPausa extends StatelessWidget {
  const _BotonPausa({
    required this.servicio,
    required this.sim,
    required this.estado,
  });

  final MqttService servicio;
  final SimulacionPista? sim;
  final Estado? estado;

  @override
  Widget build(BuildContext context) {
    final SimulacionPista? s = sim;
    final bool autonomo = s != null ? s.autonomo : estado?.modo == 'autonomo';
    final bool puede = servicio.puedeEnviarOrdenes;
    return OutlinedButton.icon(
      key: const Key('mision-pausa'),
      style: OutlinedButton.styleFrom(
        foregroundColor: autonomo ? CockpitColors.primary : CockpitColors.ok,
        side: BorderSide(
          color: (autonomo ? CockpitColors.primary : CockpitColors.ok)
              .withValues(alpha: 0.4),
        ),
        minimumSize: const Size.fromHeight(52),
      ),
      onPressed: puede
          ? () => enviarOrden(context, servicio, autonomo ? 'frenar' : 'auto')
          : null,
      icon: Icon(autonomo ? Icons.pause : Icons.play_arrow, size: 20),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(autonomo ? 'PAUSAR MISIÓN' : 'REANUDAR MISIÓN'),
      ),
    );
  }
}

class _UltimoEvento extends StatelessWidget {
  const _UltimoEvento({required this.evento});

  final EventoSim evento;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.history, size: 14, color: CockpitColors.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'ÚLTIMO EVENTO · ${evento.texto}',
            key: const Key('mision-evento'),
            softWrap: true,
            style: CockpitText.telemetrySm.copyWith(
              color: CockpitColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
