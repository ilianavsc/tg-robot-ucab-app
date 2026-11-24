import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/mqtt/mqtt_service.dart';
import '../../core/operacion/capa3_operacional.dart';
import '../../core/theme/cockpit_theme.dart';
import '../../core/pistas/trazado_pista.dart';
import 'catalogo_pistas.dart';
import 'escaneo_pista.dart';

/// **Escaneo y Validación de Pista** (Gemelo Digital + Capa 3 Operacional).
///
/// Comparte la única instancia de [Capa3OperacionalController] expuesta por
/// [MqttService] con el Dashboard para que toda configuración de ruta, parada,
/// escaneo y alerta MPU-6050 sea consistente entre pantallas.
class PantallaEscaneoPista extends StatefulWidget {
  const PantallaEscaneoPista({
    super.key,
    required this.catalogo,
    required this.pistaId,
    this.velocidadReproduccion = 9,
  });

  final CatalogoPistas catalogo;
  final String pistaId;
  final double velocidadReproduccion;

  @override
  State<PantallaEscaneoPista> createState() => _PantallaEscaneoPistaState();
}

class _PantallaEscaneoPistaState extends State<PantallaEscaneoPista>
    with SingleTickerProviderStateMixin {
  late EscaneoPista _escaneo;
  late final MqttService _servicio;
  late final TextEditingController _paradaCtrl;
  late final Ticker _ticker;
  Duration _ultimo = Duration.zero;
  bool _guardada = false;
  bool _saliendo = false;
  String? _errorValidacionParada;

  PistaLocal? get _pista => widget.catalogo.porId(widget.pistaId);
  Capa3OperacionalController get _capa3 => _servicio.capa3;

  @override
  void initState() {
    super.initState();
    _servicio = context.read<MqttService>();
    final TipoGeometriaPista geom =
        _pista?.geometria ?? TipoGeometriaPista.circuitoCerrado;
    final double largo = _pista?.longitudM ?? 9.0;
    _escaneo = EscaneoPista(
      pistaId: widget.pistaId,
      largoEstimadoM: largo,
      geometria: geom,
    );
    final bool esLineal = geom == TipoGeometriaPista.lineal;
    final String paradaInicial = esLineal ? 'Estación 1' : '';
    _paradaCtrl = TextEditingController(text: paradaInicial);
    // Inicializa sobre la única instancia compartida en MqttService y publica
    // `iniciar_escaneo` en `rutas/escaneo` para sincronizar P04/robot.
    _capa3.setLargoM(largo);
    _capa3.setTipoRuta(
      esLineal ? TipoRutaOperacional.lineal : TipoRutaOperacional.cerrada,
    );
    _capa3.configurarParada(paradaInicial);
    _servicio.iniciarEscaneoCapa3(notificar: false);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration t) {
    final double dt = (t - _ultimo).inMicroseconds / 1e6;
    _ultimo = t;
    if (dt <= 0 || _escaneo.completado) return;
    final double dtClamped = math.min(dt, 0.25);
    setState(() {
      // Reloj de Capa 3: cinemática real (0,41 m/s -> 21,95 s) acelerada
      // únicamente por el selector 1x / 2x / 4x (jamás por timeout).
      _capa3.avanzarReloj(dtClamped);
      if (_capa3.tipoRuta == TipoRutaOperacional.lineal &&
          _capa3.estadoRuta == EstadoRutaOperacional.escaneoIda &&
          _capa3.progresoPasadaM >= _capa3.largoM) {
        _servicio.completarPasadaIdaCapa3();
      } else if (_capa3.estadoRuta == EstadoRutaOperacional.escaneoRetorno &&
          _capa3.progresoPasadaM >= _capa3.largoM) {
        _servicio.completarPasadaRetornoCapa3();
      }
      // En ESPERA_REPOSICION no hay avance automático por temporizador.
      if (_capa3.estadoRuta != EstadoRutaOperacional.esperaReposicion) {
        _escaneo.avanzar(
          dtClamped * widget.velocidadReproduccion * _capa3.escalaReloj,
        );
      }
    });
    if (_escaneo.completado) _terminar();
  }

  void _cambiarTipoRuta(TipoRutaOperacional tipo) {
    setState(() {
      final TipoGeometriaPista nuevaGeom = tipo == TipoRutaOperacional.lineal
          ? TipoGeometriaPista.lineal
          : TipoGeometriaPista.circuitoCerrado;
      if (_escaneo.geometria != nuevaGeom) {
        final double largo = _pista?.longitudM ?? 9.0;
        _escaneo.dispose();
        _escaneo = EscaneoPista(
          pistaId: widget.pistaId,
          largoEstimadoM: largo,
          geometria: nuevaGeom,
        );
        _guardada = false;
        if (!_ticker.isActive) {
          _ultimo = Duration.zero;
          _ticker.start();
        }
      }
      _servicio.configurarTipoRutaCapa3(tipo);
      _servicio.configurarParadaCapa3(_paradaCtrl.text);
      if (tipo == TipoRutaOperacional.lineal && !_capa3.paradaConfigurada) {
        _errorValidacionParada =
            'Parada obligatoria en Ruta Lineal para iniciar el doble escaneo.';
      } else {
        _errorValidacionParada = null;
        _servicio.iniciarEscaneoCapa3();
      }
    });
  }

  void _actualizarParada(String valor) {
    setState(() {
      final bool ok = _servicio.configurarParadaCapa3(valor);
      if (_capa3.tipoRuta == TipoRutaOperacional.lineal && !ok) {
        _errorValidacionParada =
            'Parada obligatoria en Ruta Lineal para iniciar el doble escaneo.';
      } else {
        _errorValidacionParada = null;
        if (ok && _capa3.estadoRuta == EstadoRutaOperacional.escaneoIda) {
          _servicio.iniciarEscaneoCapa3();
        }
      }
    });
  }

  void _simularFinPasadaIda() {
    setState(() {
      if (_capa3.estadoRuta == EstadoRutaOperacional.sinRuta) {
        final ResultadoCapa3 r = _servicio.iniciarEscaneoCapa3();
        if (!r.ok) {
          _errorValidacionParada =
              'Parada obligatoria en Ruta Lineal para iniciar el doble escaneo.';
          return;
        }
      }
      _servicio.completarPasadaIdaCapa3();
    });
  }

  void _confirmarReposicionamiento() {
    setState(() {
      _servicio.confirmarReposicionamientoCapa3();
    });
  }

  void _terminar() {
    if (_guardada) return;
    if (_capa3.estadoRuta == EstadoRutaOperacional.escaneoIda &&
        _capa3.tipoRuta == TipoRutaOperacional.cerrada) {
      _servicio.completarPasadaIdaCapa3();
    } else if (_capa3.estadoRuta == EstadoRutaOperacional.escaneoRetorno) {
      _servicio.completarPasadaRetornoCapa3();
    }
    _guardada = widget.catalogo.completarEscaneo(
      widget.pistaId,
      _escaneo.metricas!,
    );
    _ticker.stop();
  }

  void _volver() {
    if (!mounted || _saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(_guardada);
  }

  @override
  void dispose() {
    _ticker.stop(canceled: true);
    _ticker.dispose();
    _paradaCtrl.dispose();
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
                  const SizedBox(height: 10),
                  _PanelCapa3Escaneo(
                    capa3: _capa3,
                    paradaCtrl: _paradaCtrl,
                    errorParada: _errorValidacionParada,
                    formato: _m,
                    onTipoRuta: _cambiarTipoRuta,
                    onParadaChanged: _actualizarParada,
                    onEscalaReloj: (int f) =>
                        setState(() => _servicio.setEscalaRelojCapa3(f)),
                    onMarcarFinIda: _simularFinPasadaIda,
                    onConfirmarReposicion: _confirmarReposicionamiento,
                  ),
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
      old.e.geometria != e.geometria ||
      old._pos != _pos ||
      old._etapa != _etapa ||
      !_iguales(old._seg, _seg);

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

/// Panel de Capa 3 en el Escaneo: selector Ruta Cerrada vs. Ruta Lineal,
/// validación de parada obligatoria en lineal, barra de tiempos reales
/// (`0,41 m/s` / `0,16 m/s`), selector de reloj Demo `1x / 2x / 4x` y botón
/// manual "Confirmar reposicionamiento" en `ESPERA_REPOSICION`.
class _PanelCapa3Escaneo extends StatelessWidget {
  const _PanelCapa3Escaneo({
    required this.capa3,
    required this.paradaCtrl,
    required this.errorParada,
    required this.formato,
    required this.onTipoRuta,
    required this.onParadaChanged,
    required this.onEscalaReloj,
    required this.onMarcarFinIda,
    required this.onConfirmarReposicion,
  });

  final Capa3OperacionalController capa3;
  final TextEditingController paradaCtrl;
  final String? errorParada;
  final String Function(double) formato;
  final ValueChanged<TipoRutaOperacional> onTipoRuta;
  final ValueChanged<String> onParadaChanged;
  final ValueChanged<int> onEscalaReloj;
  final VoidCallback onMarcarFinIda;
  final VoidCallback onConfirmarReposicion;

  @override
  Widget build(BuildContext context) {
    final bool esLineal = capa3.tipoRuta == TipoRutaOperacional.lineal;
    final bool esperandoRepos =
        capa3.estadoRuta == EstadoRutaOperacional.esperaReposicion;
    return Container(
      key: const Key('escaneo-panel-capa3'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CockpitColors.surfaceLow,
        borderRadius: BorderRadius.circular(CockpitRadius.lg),
        border: Border.all(
          color: esperandoRepos
              ? CockpitColors.warning.withValues(alpha: 0.7)
              : CockpitColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                'CONFIGURACIÓN DE RUTA · CAPA 3',
                style: CockpitText.labelMd.copyWith(
                  color: CockpitColors.primary,
                ),
              ),
              Container(
                key: const Key('escaneo-capa3-estado'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CockpitColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(CockpitRadius.sm),
                ),
                child: Text(
                  capa3.estadoRuta.clave,
                  style: CockpitText.telemetrySm.copyWith(
                    color: esperandoRepos
                        ? CockpitColors.warning
                        : CockpitColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                key: const Key('escaneo-tipo-cerrada'),
                label: const Text('Ruta Cerrada'),
                selected: !esLineal,
                onSelected: (_) => onTipoRuta(TipoRutaOperacional.cerrada),
              ),
              ChoiceChip(
                key: const Key('escaneo-tipo-lineal'),
                label: const Text('Ruta Lineal (doble escaneo)'),
                selected: esLineal,
                onSelected: (_) => onTipoRuta(TipoRutaOperacional.lineal),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('escaneo-parada-input'),
            controller: paradaCtrl,
            onChanged: onParadaChanged,
            style: CockpitText.bodyMd.copyWith(color: CockpitColors.onSurface),
            decoration: InputDecoration(
              isDense: true,
              labelText: esLineal
                  ? 'Parada de entrega (obligatoria en lineal)'
                  : 'Parada de entrega (opcional en cerrada)',
              hintText: 'Ej. Estación 1',
              errorText: errorParada,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('escaneo-tiempos-capa3'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CockpitColors.surfaceLowest,
              borderRadius: BorderRadius.circular(CockpitRadius.md),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Estimado: ${formato(capa3.duracionEstimadaEscaneoS)} s'
                  '${esLineal ? ' + pausa manual' : ''}',
                  style: CockpitText.telemetrySm.copyWith(
                    color: CockpitColors.primary,
                  ),
                ),
                Text(
                  'Sim: ${formato(capa3.tiempoSimS)} s · Real: ${formato(capa3.tiempoRealS)} s · Rest: ${formato(capa3.tiempoRestanteEstimadoS)} s',
                  style: CockpitText.telemetrySm.copyWith(
                    color: CockpitColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                'Reloj Demo:',
                style: CockpitText.labelMd.copyWith(
                  color: CockpitColors.onSurfaceVariant,
                ),
              ),
              for (final int f in Capa3OperacionalController.escalasReloj)
                ChoiceChip(
                  key: Key('escaneo-reloj-${f}x'),
                  label: Text('${f}x'),
                  selected: capa3.escalaReloj == f,
                  onSelected: (_) => onEscalaReloj(f),
                ),
              if (esLineal &&
                  capa3.estadoRuta == EstadoRutaOperacional.escaneoIda)
                OutlinedButton(
                  key: const Key('escaneo-fin-ida'),
                  onPressed: onMarcarFinIda,
                  child: const Text('Fin pasada ida'),
                ),
            ],
          ),
          if (esperandoRepos) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('escaneo-confirmar-reposicion'),
              style: FilledButton.styleFrom(
                backgroundColor: CockpitColors.warning,
                foregroundColor: CockpitColors.primaryText,
              ),
              onPressed: onConfirmarReposicion,
              icon: const Icon(Icons.rotate_90_degrees_cw),
              label: const Text('Confirmar reposicionamiento'),
            ),
          ],
        ],
      ),
    );
  }
}
