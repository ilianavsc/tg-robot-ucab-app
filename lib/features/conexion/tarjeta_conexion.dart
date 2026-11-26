import 'package:flutter/material.dart';

import '../../core/mqtt/mqtt_service.dart';
import '../../core/theme/cockpit_theme.dart';
import '../telemetria/cockpit_ui.dart';
import '../telemetria/conexion_cockpit.dart';

/// Sección **Conexión** de la operación real (User o Admin, fuera de Demo).
/// Aparece al iniciar sesión, sin necesidad del Modo Desarrollador: elige el
/// broker y establece la conexión que enciende el mini-mapa y los controles.
class TarjetaConexion extends StatelessWidget {
  const TarjetaConexion({super.key, required this.servicio});

  final MqttService servicio;

  @override
  Widget build(BuildContext context) {
    final ({String texto, Color color}) enlace = estadoEnlace(servicio);
    return CockpitCard(
      key: const Key('seccion-conexion'),
      borde: servicio.conectado
          ? CockpitColors.ok.withValues(alpha: 0.45)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(
            icono: Icons.hub_outlined,
            etiqueta: 'Conexión',
            trailing: StatusPill(texto: enlace.texto, color: enlace.color),
          ),
          const SizedBox(height: 6),
          Text(
            '${servicio.host}:${servicio.puertoEfectivo}',
            style: CockpitText.telemetrySm.copyWith(
              color: CockpitColors.onSurfaceVariant,
            ),
          ),
          if (servicio.ultimoError != null && !servicio.conectado) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              servicio.ultimoError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CockpitText.bodySm.copyWith(color: CockpitColors.error),
            ),
          ],
          const SizedBox(height: 12),
          ConexionControles(servicio: servicio),
        ],
      ),
    );
  }
}

/// Texto del mini-mapa apagado (operación real antes de conectar).
const String textoMapaApagado =
    'Sin conexión · Establece la conexión para activar el mapa y los controles';

/// Mini-mapa **apagado**: se muestra en la operación real mientras no hay
/// conexión establecida. No dibuja la pista ni permite operar.
class MapaApagado extends StatelessWidget {
  const MapaApagado({super.key, this.pista});

  /// Nombre de la pista seleccionada (se encenderá al conectar).
  final String? pista;

  @override
  Widget build(BuildContext context) {
    return CockpitCard(
      key: const Key('mapa-apagado'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.map_outlined,
                size: 18,
                color: CockpitColors.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pista == null ? 'Mini-mapa' : 'Mini-mapa · $pista',
                  overflow: TextOverflow.ellipsis,
                  style: CockpitText.labelMd.copyWith(
                    color: CockpitColors.onSurfaceVariant,
                  ),
                ),
              ),
              const StatusPill(texto: 'APAGADO', color: CockpitColors.outline),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CockpitColors.surfaceLowest,
                borderRadius: BorderRadius.circular(CockpitRadius.md),
                border: Border.all(color: CockpitColors.outlineVariant),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.power_settings_new,
                        size: 32,
                        color: CockpitColors.outline,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        textoMapaApagado,
                        key: const Key('mapa-apagado-texto'),
                        textAlign: TextAlign.center,
                        style: CockpitText.bodySm.copyWith(
                          color: CockpitColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
