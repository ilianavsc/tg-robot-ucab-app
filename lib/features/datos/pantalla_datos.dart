import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/estado.dart';
import '../../core/models/ultrasonido.dart';
import '../../core/mqtt/mqtt_service.dart';
import '../../core/theme/cockpit_theme.dart';
import '../telemetria/cockpit_datos.dart';
import '../telemetria/cockpit_ui.dart';
import 'historial_datos.dart';

String _num(double v, [int dec = 2]) => v.toStringAsFixed(dec);

String _hora(DateTime h) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(h.hour)}:${dos(h.minute)}:${dos(h.second)}';
}

/// **Consolas de sensores** (Modo Desarrollador): telemetría en vivo de
/// energía, motores, línea y ultrasonidos.
class ConsolaSensores extends StatelessWidget {
  const ConsolaSensores({super.key});

  @override
  Widget build(BuildContext context) {
    final MqttService servicio = context.watch<MqttService>();
    final Estado? estado = servicio.ultimoEstado;
    final Estado? e = estadoSinSenal(estado) ? null : estado;
    final Ultrasonido? u = servicio.ultimoUltrasonido;
    String v(String Function(Estado) f) => e == null ? '—' : f(e);
    String cm(double? x) => x == null ? '—' : '${_num(x, 1)} cm';
    return CockpitCard(
      key: const Key('consola-sensores'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(
            icono: Icons.sensors,
            etiqueta: 'Consolas de sensores',
            trailing: StatusPill(
              texto: e == null ? 'SIN SEÑAL' : 'EN VIVO',
              color: e == null ? CockpitColors.outline : CockpitColors.ok,
            ),
          ),
          const SizedBox(height: 12),
          _Fila('Paquete', v((Estado e) => '#${e.numero}')),
          _Fila('Modo', v((Estado e) => e.modo.toUpperCase())),
          _Fila('Batería', v((Estado e) => '${e.bateria} %')),
          _Fila('Tensión 3S', v((Estado e) => '${_num(e.bateriaV)} V')),
          _Fila(
            'Línea (TCRT5000)',
            v((Estado e) => '${_num(e.lineaMm, 1)} mm'),
          ),
          _Fila('Motor izq.', v((Estado e) => '${_num(e.vIzq)} m/s')),
          _Fila('Motor der.', v((Estado e) => '${_num(e.vDer)} m/s')),
          _Fila('Ultrasonido frente', cm(u?.frenteValido)),
          _Fila('Ultrasonido atrás', cm(u?.atrasValido)),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.valor);

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              etiqueta.toUpperCase(),
              style: CockpitText.telemetrySm.copyWith(
                color: CockpitColors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            valor,
            style: CockpitText.telemetryMd.copyWith(
              color: CockpitColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// **Historial de datos** (Modo Desarrollador): últimas lecturas registradas.
class TarjetaHistorialDatos extends StatelessWidget {
  const TarjetaHistorialDatos({super.key, this.maximo = 25});

  /// Filas visibles (las más recientes).
  final int maximo;

  @override
  Widget build(BuildContext context) {
    final HistorialDatos? historial = context.watch<HistorialDatos?>();
    final List<LecturaHistorial> lecturas =
        historial?.lecturas ?? const <LecturaHistorial>[];
    return CockpitCard(
      key: const Key('historial-datos'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(
            icono: Icons.history,
            etiqueta: 'Historial de datos',
            trailing: StatusPill(
              texto: '${lecturas.length}',
              color: CockpitColors.primary,
              punto: false,
            ),
          ),
          const SizedBox(height: 10),
          if (lecturas.isEmpty)
            Text(
              'Sin lecturas todavía.',
              style: CockpitText.bodySm.copyWith(
                color: CockpitColors.onSurfaceVariant,
              ),
            )
          else
            for (final LecturaHistorial l in lecturas.take(maximo))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${_hora(l.hora)}  #${l.numero}  ${l.bateria}%  '
                  '${_num(l.lineaMm, 1)}mm  '
                  'F ${l.frenteCm == null ? '—' : _num(l.frenteCm!, 0)}cm',
                  style: CockpitText.telemetrySm.copyWith(
                    color: CockpitColors.onSurface,
                  ),
                ),
              ),
          if (historial != null && lecturas.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('historial-limpiar'),
                onPressed: historial.limpiar,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Limpiar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sección **DATOS** del Modo Desarrollador: consolas de sensores e
/// historial de datos.
class PantallaDatos extends StatelessWidget {
  const PantallaDatos({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('pantalla-datos'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: const <Widget>[
        ConsolaSensores(),
        SizedBox(height: 12),
        TarjetaHistorialDatos(),
      ],
    );
  }
}

/// La sección DATOS como pantalla propia (abierta desde Perfil).
class PaginaDatos extends StatelessWidget {
  const PaginaDatos({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CockpitColors.surfaceLowest,
        title: Text(
          'CONSOLAS E HISTORIAL',
          style: CockpitText.labelMd.copyWith(
            fontSize: 14,
            color: CockpitColors.onSurface,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const PantallaDatos(),
        ),
      ),
    );
  }
}
