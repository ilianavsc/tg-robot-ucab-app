import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/mqtt/mqtt_service.dart';
import '../auth/sesion_local.dart';

/// `true` si la sesión activa es de **Demo**. Sin `SesionLocal` en el árbol
/// (pruebas de componentes aisladas) devuelve `false`.
bool sesionEsDemo(BuildContext context, {bool escuchar = true}) {
  try {
    return Provider.of<SesionLocal>(context, listen: escuchar).demo;
  } on ProviderNotFoundException {
    return false;
  }
}

/// `true` si el mini-mapa y la operación (pedidos, recorrido, órdenes) están
/// habilitados.
///
/// * **Demo**: siempre (telemetría simulada, sin conexión).
/// * **Operación real** (User o Admin): solo con la conexión al broker
///   **establecida**; antes el mini-mapa aparece apagado.
/// * Sin sesión activa o sin `SesionLocal` en el árbol (pruebas de
///   componentes aisladas): habilitado, para no alterar esas pruebas.
bool operacionHabilitada(BuildContext context) {
  final MqttService servicio = Provider.of<MqttService>(context);
  try {
    final SesionLocal sesion = Provider.of<SesionLocal>(context);
    if (!sesion.activa || sesion.demo) return true;
  } on ProviderNotFoundException {
    return true;
  }
  return servicio.conectado || servicio.simulando;
}
