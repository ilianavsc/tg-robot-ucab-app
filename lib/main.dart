import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/mqtt/mqtt_service.dart';
import 'core/theme/cockpit_theme.dart';
import 'features/auth/catalogo_pistas.dart';
import 'features/auth/pantalla_login.dart';
import 'features/auth/registro_usuarios.dart';
import 'features/auth/sesion_local.dart';
import 'features/datos/historial_datos.dart';
import 'features/perfil/aprendizaje_ruta.dart';
import 'features/telemetria/telemetria_screen.dart';

/// Punto de entrada de la app.
///
/// `MqttService` se crea una sola vez y vive en el árbol: cualquier pantalla
/// puede escucharlo con `context.watch<MqttService>()`. **No** se conecta al
/// abrir la app: en la operación real el usuario establece la conexión desde
/// la sección **Conexión** (el mini-mapa permanece apagado hasta entonces) y
/// la Demo no usa red.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppRobotUcab());
}

class AppRobotUcab extends StatelessWidget {
  const AppRobotUcab({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<MqttService>(create: (_) => MqttService()),
        // Historial de datos (Modo Desarrollador): escucha la telemetría.
        ChangeNotifierProvider<HistorialDatos>(
          lazy: false,
          create: (BuildContext ctx) => HistorialDatos(ctx.read<MqttService>()),
        ),
        // Autenticación local (mock, sin backend): rol de la sesión.
        ChangeNotifierProvider<SesionLocal>(create: (_) => SesionLocal()),
        ChangeNotifierProvider<RegistroUsuarios>(
          create: (_) => RegistroUsuarios(),
        ),
        // Aprendizaje de ruta (solo Admin, SIL en memoria): la usa el Operador.
        ChangeNotifierProvider<AprendizajeRuta>(
          create: (_) => AprendizajeRuta(),
        ),
        ChangeNotifierProvider<CatalogoPistas>(create: (_) => CatalogoPistas()),
      ],
      child: MaterialApp(
        title: 'TG Robot UCAB',
        debugShowCheckedModeBanner: false,
        // Versión oscura nativa del portafolio: se fuerza el modo oscuro.
        theme: buildCockpitTheme(),
        darkTheme: buildCockpitTheme(),
        themeMode: ThemeMode.dark,
        home: const PuertaAcceso(),
      ),
    );
  }
}

/// Muestra la pantalla de inicio (Pistas · Login · Demo) mientras no haya
/// sesión local y la telemetría cuando la hay. Cerrar sesión
/// (`SesionLocal.cerrar`) devuelve al inicio.
class PuertaAcceso extends StatelessWidget {
  const PuertaAcceso({super.key});

  @override
  Widget build(BuildContext context) {
    final bool activa = context.select<SesionLocal, bool>((s) => s.activa);
    return activa ? const TelemetriaScreen() : const PantallaLogin();
  }
}
