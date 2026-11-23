import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/cockpit_theme.dart';
import '../../core/pistas/trazado_pista.dart';
import 'catalogo_pistas.dart';
import 'escaneo_pista.dart';

/// **Escaneo y Validación de Pista** (Gemelo Digital, modo básico).
///
/// Se abre al crear una pista desde `+ Nueva pista`. Recorre solo, sin
/// controles manuales ni inyección de fallos, las 3 etapas adaptadas de SIM2:
/// Lectura lenta → Pasada normal → Viajes 1/3, 2/3 y 3/3. Al terminar marca la
/// pista como configurada, la deja activa y vuelve al Login.
///
/// Es una simulación (SIL) reproducida a [velocidadReproduccion]× para que
/// el escaneo dure unos segundos en pantalla.
class PantallaEscaneoPista extends StatefulWidget {
  const PantallaEscaneoPista({
    super.key,
    required this.catalogo,
    required this.pistaId,
    this.velocidadReproduccion = 9,
    this.volverAlTerminar = const Duration(milliseconds: 1800),
  });

  final CatalogoPistas catalogo;
  final String pistaId;
  final double velocidadReproduccion;

  /// Espera antes de volver solo al Login cuando el escaneo termina.
  final Duration volverAlTerminar;

  @override
  State<PantallaEscaneoPista> createState() => _PantallaEscaneoPistaState();
}

class _PantallaEscaneoPistaState extends State<PantallaEscaneoPista>
    with SingleTickerProviderStateMixin {
  late final EscaneoPista _escaneo;
  late final Ticker _ticker;
  Duration _ultimo = Duration.zero;
  bool _guardada = false;
  bool _saliendo = false;

  PistaLocal? get _pista => widget.catalogo.porId(widget.pistaId);

  @override
  void initState() {
    super.initState();
    _escaneo = EscaneoPista(
      pistaId: widget.pistaId,
      largoEstimadoM: _pista?.longitudM ?? 9.0,
      geometria: _pista?.geometria ?? TipoGeometriaPista.circuitoCerrado,
    );
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration t) {
    final double dt = (t - _ultimo).inMicroseconds / 1e6;
    _ultimo = t;
    if (dt <= 0 || _escaneo.completado) return;
    setState(
      () => _escaneo.avanzar(math.min(dt, 0.25) * widget.velocidadReproduccion),
    );
    if (_escaneo.completado) _terminar();
  }

  void _terminar() {
    if (_guardada) return;
    _guardada = widget.catalogo.completarEscaneo(
      widget.pistaId,
      _escaneo.metricas!,
    );
    _ticker.stop();
    Future<void>.delayed(widget.volverAlTerminar, _volver);
  }

  void _volver() {
    if (!mounted || _saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(_guardada);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _escaneo.dispose();
    super.dispose();
  }

  String _m(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final PistaLocal? pista = _pista;
    final bool listo = _escaneo.completado;
    return Scaffold(
      backgroundColor: CockpitColors.surface,
      appBar: AppBar(
        backgroundColor: CockpitColors.surface,
        centerTitle: true,
        leading: IconButton(
          key: const Key('escaneo-salir'),
          tooltip: 'Salir del escaneo (la pista queda pendiente)',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(_guardada),
        ),
        title: Text(
          'Escaneo de pista',
          style: CockpitText.titleMd.copyWith(color: CockpitColors.onSurface),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('escaneo-lista'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Cabecera(
                    nombre: pista?.nombre ?? '—',
                    configurada: listo && _guardada,
                  ),
                  const SizedBox(height: 10),
                  const _AvisoCalibracionAdmin(),
                  const SizedBox(height: 12),
                  _Lienzo(escaneo: _escaneo),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('escaneo-progreso'),
                      value: _escaneo.progresoTotal,
                      minHeight: 6,
                      backgroundColor: CockpitColors.surfaceHigh,
                      color: listo ? CockpitColors.ok : CockpitColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    listo
                        ? 'Escaneo completo · ${_escaneo.tiempoTotalS.toStringAsFixed(0)} s simulados'
                        : '${_escaneo.etapa.titulo}'
                              '${_escaneo.etapa.esViaje ? ' (lectura ${_escaneo.lecturaActualEnSegmento}/3)' : ''}'
                              ' · ${_m(_escaneo.posicionM)} m · '
                              '${_m(_escaneo.velocidadMs)} m/s',
                    key: const Key('escaneo-estado'),
                    style: CockpitText.telemetrySm.copyWith(
                      color: CockpitColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Etapas(escaneo: _escaneo),
                  const SizedBox(height: 14),
                  _Datos(escaneo: _escaneo, formato: _m),
                  const SizedBox(height: 14),
                  if (listo)
                    FilledButton.icon(
                      key: const Key('escaneo-listo'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _volver,
                      icon: const Icon(Icons.login),
                      label: const Text(
                        'Pista configurada · ir a iniciar sesión',
                      ),
                    )
                  else
                    Text(
                      'Simulación (SIL) en modo básico: sin torres de control. '
                      'Los valores son de la vuelta simulada [PENDIENTE DE MEDICIÓN FÍSICA].',
                      style: CockpitText.bodySm.copyWith(
                        color: CockpitColors.outline,
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

/// Aviso visible durante toda la calibración: proceso guiado por Administrador
/// con la pista despejada de obstáculos temporales.
class _AvisoCalibracionAdmin extends StatelessWidget {
  const _AvisoCalibracionAdmin();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('escaneo-aviso-admin'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CockpitColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(CockpitRadius.md),
        border: Border.all(
          color: CockpitColors.warning.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.admin_panel_settings_outlined,
            size: 18,
            color: CockpitColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Calibración guiada por Administrador',
                  style: CockpitText.labelMd.copyWith(
                    color: CockpitColors.warning,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Garantiza que no haya obstáculos temporales en la pista '
                  'para aprender únicamente las paredes fijas del entorno.',
                  style: CockpitText.bodySm.copyWith(
                    color: CockpitColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.nombre, required this.configurada});

  final String nombre;
  final bool configurada;

  @override
  Widget build(BuildContext context) {
    final Color c = configurada ? CockpitColors.ok : CockpitColors.warning;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            nombre,
            key: const Key('escaneo-pista-nombre'),
            overflow: TextOverflow.ellipsis,
            style: CockpitText.headlineSm.copyWith(
              color: CockpitColors.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          key: const Key('escaneo-estado-pista'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: ShapeDecoration(
            color: c.withValues(alpha: 0.14),
            shape: StadiumBorder(side: BorderSide(color: c)),
          ),
          child: Text(
            configurada
                ? EstadoPista.configurada.etiqueta.toUpperCase()
                : 'PENDIENTE · EN ESCANEO',
            style: CockpitText.labelMd.copyWith(color: c),
          ),
        ),
      ],
    );
  }
}

/// Vista compacta tipo consola de la pista: circuito cerrado, robot, PC1–PC3,
/// segmento activo y segmentos ya validados.
class _Lienzo extends StatelessWidget {
  const _Lienzo({required this.escaneo});

  final EscaneoPista escaneo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Pista en escaneo: ${escaneo.etapa.titulo}, '
          'robot en ${escaneo.posicionM.toStringAsFixed(1)} m',
      child: Container(
        key: const Key('escaneo-lienzo'),
        width: double.infinity,
        height: 210,
        decoration: BoxDecoration(
          color: CockpitColors.surfaceLowest,
          borderRadius: BorderRadius.circular(CockpitRadius.lg),
          border: Border.all(
            color: CockpitColors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: CustomPaint(
          key: const Key('escaneo-lienzo-paint'),
          painter: _PintorEscaneo(escaneo),
        ),
      ),
    );
  }
}

class _PintorEscaneo extends CustomPainter {
  _PintorEscaneo(this.e)
    : _pos = e.posicionM,
      _etapa = e.etapa,
      _seg = List<bool>.of(e.segmentosValidados);

  final EscaneoPista e;
  final double _pos;
  final EtapaEscaneo _etapa;
  final List<bool> _seg;

  @override
  void paint(Canvas canvas, Size size) {
    final double margenX = math.max(36, size.width * 0.08);
    final Rect r = Rect.fromLTRB(
      margenX,
      44,
      math.max(margenX + 40, size.width - margenX),
      math.max(84, size.height - 38),
    );
    final double largo = e.largoM;
    // Trazado subyacente descubierto progresivamente (nunca pre-dibujado antes).
    final TrazadoPista trazado = TrazadoPista.paraPista(
      e.pistaId,
      largo,
      geometria: e.geometria,
    );
    final Path camino = caminoEnLienzo(trazado, r);
    final PathMetric m = camino.computeMetrics().first;
    double f(double metros) => (metros / largo).clamp(0.0, 1.0) * m.length;

    // Fondo digital en blanco con cuadrícula tenue (sin silueta previa)
    final Paint rejilla = Paint()
      ..color = CockpitColors.outlineVariant.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), rejilla);
    }
    for (double y = 0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rejilla);
    }

    final bool enLenta = _etapa == EtapaEscaneo.lecturaLenta;
    final bool enNormal = _etapa == EtapaEscaneo.pasadaNormal;
    final bool enSecciones = _etapa.esViaje || _etapa == EtapaEscaneo.completado;

    // Encuadre del fondo digital: en Fase 1 crece con lo recorrido; desde Fase 2
    // queda fijado con las dimensiones medidas del plano.
    if (enLenta) {
      if (_pos > 0.02) {
        final Path descubierto = m.extractPath(0, f(_pos));
        final Rect marco = descubierto.getBounds().inflate(10);
        canvas.drawRect(
          marco,
          Paint()
            ..color = CockpitColors.warning.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        _punteado(
          canvas,
          descubierto,
          CockpitColors.warning.withValues(alpha: 0.85),
          2.6,
        );
      }
    } else if (enNormal) {
      // Fondo acotado + primer dibujo digital trazado en vivo (0 -> _pos)
      final Rect marcoFijo = camino.getBounds().inflate(10);
      canvas.drawRect(
        marcoFijo,
        Paint()
          ..color = CockpitColors.outlineVariant.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      if (_pos > 0.02) {
        canvas.drawPath(
          m.extractPath(0, f(_pos)),
          Paint()
            ..color = CockpitColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
    } else if (enSecciones) {
      // Ruta digital V1 descubierta en Fase 2 + consolidación por sección
      final Rect marcoFijo = camino.getBounds().inflate(10);
      canvas.drawRect(
        marcoFijo,
        Paint()
          ..color = CockpitColors.outlineVariant.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawPath(
        camino,
        Paint()
          ..color = CockpitColors.outlineVariant.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      if (e.puntosControlM.length == 3) {
        final List<(double, double)> tramos = <(double, double)>[
          (0, e.puntosControlM[0]),
          (e.puntosControlM[0], e.puntosControlM[1]),
          (e.puntosControlM[1], largo),
        ];
        for (int i = 0; i < 3; i++) {
          final bool activo = _etapa.segmento == i;
          if (!_seg[i] && !activo) continue;
          canvas.drawPath(
            m.extractPath(f(tramos[i].$1), f(tramos[i].$2)),
            Paint()
              ..color = _seg[i]
                  ? CockpitColors.ok
                  : CockpitColors.primary.withValues(alpha: 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5.5,
          );
        }
      }
      final (double a, double _) = e.tramoActual;
      if (_etapa != EtapaEscaneo.completado && _pos > a) {
        canvas.drawPath(
          m.extractPath(f(a), f(_pos)),
          Paint()
            ..color = CockpitColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Inicio visible desde el primer avance; PC1–PC3 se revelan en Fase 2
    final List<double> pcEquitativos = puntosControlEquitativos(largo);
    final List<double> pc = enLenta
        ? const <double>[]
        : (e.puntosControlM.isEmpty
              ? pcEquitativos.where((double p) => p <= _pos).toList()
              : e.puntosControlM);
    final Offset inicioPos = m.getTangentForOffset(0)!.position;
    _marca(
      canvas,
      inicioPos,
      'INICIO',
      CockpitColors.onSurfaceVariant,
      abajo: trazado.cerrada ? inicioPos.dy > r.center.dy : false,
    );
    for (int i = 0; i < pc.length; i++) {
      final Offset q = m.getTangentForOffset(f(pc[i]))!.position;
      final String etq = i == 2 ? 'PC3 / META' : 'PC${i + 1}';
      _rombo(
        canvas,
        q,
        etq,
        abajo: trazado.cerrada ? q.dy > r.center.dy : true,
      );
    }

    // robot
    final Tangent t = m.getTangentForOffset(
      _etapa == EtapaEscaneo.completado
          ? (trazado.cerrada ? 0 : m.length)
          : f(_pos),
    )!;
    canvas.drawCircle(
      t.position,
      13,
      Paint()..color = CockpitColors.primary.withValues(alpha: 0.18),
    );
    canvas.drawCircle(t.position, 7, Paint()..color = CockpitColors.primary);
    canvas.drawLine(
      t.position,
      t.position + t.vector * 12,
      Paint()
        ..color = CockpitColors.primaryText
        ..strokeWidth = 2,
    );

    // rótulo de la etapa
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: _etapa == EtapaEscaneo.completado
            ? 'SEGMENTOS 1–3 VALIDADOS'
            : _etapa.titulo.toUpperCase(),
        style: CockpitText.telemetrySm.copyWith(
          color: _etapa == EtapaEscaneo.completado
              ? CockpitColors.ok
              : CockpitColors.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 20);
    tp.paint(canvas, const Offset(10, 8));
  }

  void _punteado(Canvas c, Path path, Color color, double ancho) {
    final Paint pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho
      ..strokeCap = StrokeCap.round;
    for (final PathMetric pm in path.computeMetrics()) {
      for (double d = 0; d < pm.length; d += 12) {
        c.drawPath(pm.extractPath(d, math.min(d + 6, pm.length)), pincel);
      }
    }
  }

  void _marca(Canvas c, Offset p, String txt, Color col, {bool abajo = false}) {
    c.drawRect(
      Rect.fromCenter(center: p, width: 4, height: 16),
      Paint()..color = col,
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: txt,
        style: CockpitText.telemetrySm.copyWith(color: col, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p + Offset(6, abajo ? 6 : -18));
  }

  void _rombo(Canvas c, Offset p, String txt, {bool abajo = true}) {
    final Path d = Path()
      ..moveTo(p.dx, p.dy - 7)
      ..lineTo(p.dx + 7, p.dy)
      ..lineTo(p.dx, p.dy + 7)
      ..lineTo(p.dx - 7, p.dy)
      ..close();
    c.drawPath(d, Paint()..color = CockpitColors.surfaceLowest);
    c.drawPath(
      d,
      Paint()
        ..color = CockpitColors.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: txt,
        style: CockpitText.telemetrySm.copyWith(
          color: CockpitColors.secondary,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, p + Offset(-tp.width / 2, abajo ? 9 : -22));
  }

  @override
  bool shouldRepaint(_PintorEscaneo old) =>
      old._pos != _pos || old._etapa != _etapa || !_iguales(old._seg, _seg);

  static bool _iguales(List<bool> a, List<bool> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Lista de etapas con su estado (hecha, en curso, en espera).
class _Etapas extends StatelessWidget {
  const _Etapas({required this.escaneo});

  final EscaneoPista escaneo;

  @override
  Widget build(BuildContext context) {
    final List<EtapaEscaneo> etapas = EtapaEscaneo.values
        .where((EtapaEscaneo e) => e != EtapaEscaneo.completado)
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CockpitColors.surfaceLow,
        borderRadius: BorderRadius.circular(CockpitRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final EtapaEscaneo e in etapas)
            _FilaEtapa(
              etapa: e,
              hecha: escaneo.etapa.index > e.index,
              activa: escaneo.etapa == e,
              progreso: escaneo.etapa == e ? escaneo.progresoEtapa : 0,
            ),
        ],
      ),
    );
  }
}

class _FilaEtapa extends StatelessWidget {
  const _FilaEtapa({
    required this.etapa,
    required this.hecha,
    required this.activa,
    required this.progreso,
  });

  final EtapaEscaneo etapa;
  final bool hecha;
  final bool activa;
  final double progreso;

  @override
  Widget build(BuildContext context) {
    final Color c = hecha
        ? CockpitColors.ok
        : (activa ? CockpitColors.primary : CockpitColors.outline);
    return Padding(
      key: Key('etapa-${etapa.name}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            hecha
                ? Icons.check_circle
                : (activa ? Icons.radar : Icons.radio_button_unchecked),
            size: 18,
            color: c,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  etapa.titulo,
                  style: CockpitText.labelMd.copyWith(color: c),
                ),
                Text(
                  etapa.detalle,
                  style: CockpitText.bodySm.copyWith(
                    color: CockpitColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              hecha ? 'OK' : (activa ? '${(progreso * 100).round()} %' : '—'),
              key: Key('etapa-${etapa.name}-estado'),
              textAlign: TextAlign.right,
              style: CockpitText.telemetrySm.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// Datos recolectados por etapa.
class _Datos extends StatelessWidget {
  const _Datos({required this.escaneo, required this.formato});

  final EscaneoPista escaneo;
  final String Function(double) formato;

  @override
  Widget build(BuildContext context) {
    final EscaneoPista e = escaneo;
    final List<(String, String)> filas = <(String, String)>[
      ('Tipo de pista', e.geometria.etiqueta),
      (
        'Largo (odometría)',
        e.largoMedidoM == null
            ? 'verificando…'
            : '${formato(e.largoMedidoM!)} m · ${e.cuentasOdometria} cuentas'
                  '${e.distanciaVerificada ? ' · OK' : ''}',
      ),
      (
        'Radar HC-SR04P (perfil)',
        e.frenteMedioCm == null
            ? '—'
            : 'mín. ${e.frenteMinimoCm!.toStringAsFixed(0)} cm · medio ${e.frenteMedioCm!.toStringAsFixed(0)} cm',
      ),
      (
        'Sensores base',
        e.largoMedidoM == null
            ? '—'
            : 'TCRT5000 100 % · MPU-6050 ${e.geometria == TipoGeometriaPista.lineal ? '0°' : '360°'} · odometría',
      ),
      (
        'PC1 · PC2 · PC3 (L/3)',
        e.puntosControlM.isEmpty
            ? '—'
            : e.puntosControlM.map((double v) => '${formato(v)} m').join(' · '),
      ),
      (
        'Paredes fijas (radar)',
        e.firmaParedesCm.isEmpty
            ? '—'
            : e.firmaParedesCm
                  .map((double v) => '${v.toStringAsFixed(0)} cm')
                  .join(' · '),
      ),
      (
        'Lecturas por segmento',
        '${e.lecturasSegmento.map((int n) => '$n/3').join(' · ')} (${e.totalLecturasCompletadas}/9)',
      ),
      (
        'Segmentos validados',
        '${e.segmentosValidados.where((bool v) => v).length}/3',
      ),
    ];
    return Container(
      key: const Key('escaneo-datos'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CockpitColors.surfaceLow,
        borderRadius: BorderRadius.circular(CockpitRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'DATOS RECOLECTADOS',
            style: CockpitText.labelMd.copyWith(
              color: CockpitColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final (String k, String v) in filas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Text(
                      k,
                      style: CockpitText.bodySm.copyWith(
                        color: CockpitColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7,
                    child: Text(
                      v,
                      textAlign: TextAlign.right,
                      style: CockpitText.telemetrySm.copyWith(
                        color: CockpitColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
