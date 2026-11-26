import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:robot_ucab_app/core/models/estado.dart';
import 'package:robot_ucab_app/core/mqtt/mqtt_service.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';
import 'package:robot_ucab_app/features/auth/catalogo_pistas.dart';
import 'package:robot_ucab_app/features/auth/pantalla_login.dart';
import 'package:robot_ucab_app/features/auth/registro_usuarios.dart';
import 'package:robot_ucab_app/features/auth/sesion_local.dart';
import 'package:robot_ucab_app/features/conexion/tarjeta_conexion.dart';
import 'package:robot_ucab_app/features/datos/historial_datos.dart';
import 'package:robot_ucab_app/features/perfil/aprendizaje_ruta.dart';
import 'package:robot_ucab_app/features/perfil/gestion_usuarios.dart';
import 'package:robot_ucab_app/features/perfil/pantalla_perfil.dart';
import 'package:robot_ucab_app/features/telemetria/conexion_cockpit.dart';
import 'package:robot_ucab_app/features/telemetria/mapa_pista.dart';
import 'package:robot_ucab_app/main.dart' show PuertaAcceso;

Future<void> _cargarFuentes() async {
  Future<ByteData> f(String ruta) async =>
      ByteData.sublistView(await File(ruta).readAsBytes());
  final FontLoader inter = FontLoader('Inter')
    ..addFont(f('assets/fonts/Inter-Regular.otf'))
    ..addFont(f('assets/fonts/Inter-SemiBold.otf'))
    ..addFont(f('assets/fonts/Inter-Bold.otf'));
  final FontLoader mono = FontLoader('JetBrainsMono')
    ..addFont(f('assets/fonts/JetBrainsMono-Regular.ttf'))
    ..addFont(f('assets/fonts/JetBrainsMono-Medium.ttf'))
    ..addFont(f('assets/fonts/JetBrainsMono-SemiBold.ttf'))
    ..addFont(f('assets/fonts/JetBrainsMono-Bold.ttf'));
  await inter.load();
  await mono.load();
}

class _Entorno {
  _Entorno(
    this.servicio,
    this.sesion,
    this.registro,
    this.catalogo,
    this.historial,
  );
  final MqttService servicio;
  final SesionLocal sesion;
  final RegistroUsuarios registro;
  final CatalogoPistas catalogo;
  final HistorialDatos historial;
}

/// Monta la app completa como en `main.dart` (inicio → telemetría).
Future<_Entorno> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final MqttService servicio = MqttService();
  final SesionLocal sesion = SesionLocal();
  final RegistroUsuarios registro = RegistroUsuarios();
  final CatalogoPistas catalogo = CatalogoPistas();
  final HistorialDatos historial = HistorialDatos(servicio);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MqttService>.value(value: servicio),
        ChangeNotifierProvider<SesionLocal>.value(value: sesion),
        ChangeNotifierProvider<RegistroUsuarios>.value(value: registro),
        ChangeNotifierProvider<CatalogoPistas>.value(value: catalogo),
        ChangeNotifierProvider<HistorialDatos>.value(value: historial),
        ChangeNotifierProvider<AprendizajeRuta>(
          create: (_) => AprendizajeRuta(),
        ),
      ],
      child: MaterialApp(
        theme: buildCockpitTheme(),
        home: const PuertaAcceso(),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  return _Entorno(servicio, sesion, registro, catalogo, historial);
}

Future<void> _cerrar(WidgetTester t, _Entorno e) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpWidget(const SizedBox());
  e.historial.dispose();
  e.servicio.dispose();
  e.sesion.dispose();
  e.registro.dispose();
  e.catalogo.dispose();
}

Finder _scrollDe(Type pantalla) => find
    .descendant(of: find.byType(pantalla), matching: find.byType(Scrollable))
    .first;

Future<void> _tocar(WidgetTester t, Finder f, {Type? en}) async {
  if (f.evaluate().isEmpty && en != null) {
    await t.scrollUntilVisible(f, 300, scrollable: _scrollDe(en));
  }
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _entrar(WidgetTester t, {required bool admin}) async {
  await _tocar(t, find.byKey(const Key('login-abrir')));
  await _tocar(
    t,
    find.byKey(Key(admin ? 'rol-administrador' : 'rol-operador')),
  );
  final String u = admin ? 'admin' : 'user';
  await t.enterText(find.byKey(const Key('login-usuario')), u);
  await t.enterText(find.byKey(const Key('login-clave')), u);
  await _tocar(t, find.byKey(const Key('login-entrar')));
}

Future<void> _abrirPerfil(WidgetTester t) =>
    _tocar(t, find.byKey(const Key('boton-perfil')));

Future<void> _volver(WidgetTester t) async {
  await t.tap(find.byTooltip('Volver'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(_cargarFuentes);

  group('1 · Estética oscura del portafolio', () {
    test(
      'tokens: fondo #0B0F19, tarjetas #111827, bordes #1E293B, acentos',
      () {
        expect(CockpitColors.surface, const Color(0xFF0B0F19));
        expect(CockpitColors.surfaceLow, const Color(0xFF111827));
        expect(CockpitColors.outlineVariant, const Color(0xFF1E293B));
        expect(CockpitColors.primary, const Color(0xFF2DD4BF));
        expect(CockpitColors.primaryDim, const Color(0xFF06B6D4));
        expect(CockpitColors.warning, const Color(0xFFF59E0B));
        final ThemeData tema = buildCockpitTheme();
        expect(tema.brightness, Brightness.dark);
        expect(tema.scaffoldBackgroundColor, CockpitColors.surface);
        expect(tema.colorScheme.primary, CockpitColors.primary);
      },
    );
  });

  group('2 · Inicio con 3 botones', () {
    testWidgets(
      'solo Pistas, Login y Demo; Login colapsable; Pista A predeterminada',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        expect(find.byType(BotonInicio), findsNWidgets(3));
        expect(find.byType(FilledButton), findsNothing);
        expect(e.catalogo.activa!.id, 'A');
        expect(
          find.text('Activa: Pista A · Circuito histórico'),
          findsOneWidget,
        );
        // Login plegado
        expect(find.byKey(const Key('login-tarjeta')), findsNothing);
        await _tocar(t, find.byKey(const Key('login-abrir')));
        expect(find.byKey(const Key('login-tarjeta')), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const Key('login-pista-activa'))).data,
          contains('Pista A'),
        );
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets('sin pista seleccionada no entra ni User ni Admin', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      e.catalogo.eliminarPista('A');
      await t.pump();
      for (final bool admin in <bool>[false, true]) {
        if (find.byKey(const Key('login-usuario')).evaluate().isEmpty) {
          await _tocar(t, find.byKey(const Key('login-abrir')));
        }
        await _tocar(
          t,
          find.byKey(Key(admin ? 'rol-administrador' : 'rol-operador')),
        );
        final String u = admin ? 'admin' : 'user';
        await t.enterText(find.byKey(const Key('login-usuario')), u);
        await t.enterText(find.byKey(const Key('login-clave')), u);
        await _tocar(t, find.byKey(const Key('login-entrar')));
        expect(e.sesion.activa, isFalse);
        expect(find.text(avisoSinPista), findsWidgets);
      }
      await _cerrar(t, e);
    });
  });

  group('3 · Modo Demo', () {
    testWidgets(
      'carga Admin + Pista C lineal de 2 segmentos y no muestra nada de Conexión',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-demo')));
        expect(e.sesion.demo, isTrue);
        expect(e.sesion.rol, RolUsuario.administrador);
        expect(e.sesion.nombre, 'Admin (Demo)');
        final PistaLocal c = e.catalogo.activa!;
        expect(c.id, 'C');
        expect(c.esLineal, isTrue);
        expect(c.metricas!.puntosControlM, <double>[3.0, 6.0]);
        expect(c.metricas!.segmentosValidados.length, 2);
        expect(c.metricas!.completa, isTrue);
        // Mini-mapa encendido con trazado lineal y 2 segmentos
        expect(find.byKey(const Key('mapa-apagado')), findsNothing);
        final PintorPista pintor =
            t
                    .widget<CustomPaint>(
                      find.byKey(const Key('mapa-pista-lienzo')),
                    )
                    .painter!
                as PintorPista;
        expect(pintor.trazado!.cerrada, isFalse);
        expect(pintor.puntosControlM, <double>[3.0, 6.0]);
        expect(
          t.widget<Text>(find.byKey(const Key('mapa-estaciones'))).data,
          'Inicio 0,0 · PC1 3,0 · PC2 6,0 m',
        );
        expect(find.textContaining('Pista C'), findsWidgets);
        // Nada de Conexión
        expect(find.byKey(const Key('boton-conexion')), findsNothing);
        expect(find.byKey(const Key('seccion-conexion')), findsNothing);
        expect(find.byType(ConexionControles), findsNothing);
        expect(find.text('Conexión'), findsNothing);
        // Ni siquiera con el Modo Desarrollador encendido
        await _abrirPerfil(t);
        expect(find.text('ENLACE MQTT'), findsNothing);
        await _tocar(
          t,
          find.byKey(const Key('perfil-modo-desarrollador')),
          en: PantallaPerfil,
        );
        expect(e.sesion.modoDesarrollador, isTrue);
        expect(find.text('ENLACE MQTT'), findsNothing);
        expect(find.byKey(const Key('perfil-broker')), findsNothing);
        await _volver(t);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byKey(const Key('boton-conexion')), findsNothing);
        expect(find.byType(ConexionControles), findsNothing);
        expect(find.textContaining('ENLACE MQTT'), findsNothing);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets(
      'el interruptor del Perfil cambia en vivo entre Admin (Demo) y User (Demo)',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-demo')));
        await _abrirPerfil(t);
        final Finder sw = find.byKey(const Key('perfil-demo-admin'));
        expect(sw, findsOneWidget);
        expect(t.widget<Switch>(sw).value, isTrue);
        expect(find.text('PERFIL · ADMIN'), findsOneWidget);
        expect(find.byKey(const Key('perfil-usuarios')), findsOneWidget);
        // → User (Demo)
        await _tocar(t, sw);
        expect(e.sesion.rol, RolUsuario.operador);
        expect(e.sesion.nombre, 'User (Demo)');
        expect(e.sesion.demo, isTrue);
        expect(t.widget<Switch>(sw).value, isFalse);
        expect(find.text('PERFIL · USER'), findsOneWidget);
        expect(find.byKey(const Key('perfil-usuarios')), findsNothing);
        expect(
          find.byKey(const Key('perfil-modo-desarrollador')),
          findsNothing,
        );
        // El User (Demo) configura un pedido/solicitud en la vista limpia
        await _volver(t);
        expect(find.byKey(const Key('vista-limpia')), findsOneWidget);
        expect(find.byKey(const Key('capa3-solicitar-pedido')), findsOneWidget);
        expect(find.byKey(const Key('boton-conexion')), findsNothing);
        expect(e.servicio.simulando, isTrue);
        // → Admin (Demo) otra vez
        await _abrirPerfil(t);
        await _tocar(t, find.byKey(const Key('perfil-demo-admin')));
        expect(e.sesion.rol, RolUsuario.administrador);
        expect(e.sesion.nombre, 'Admin (Demo)');
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    test('el interruptor de cuenta solo funciona en Demo', () {
      final SesionLocal s = SesionLocal();
      s.iniciar(RolUsuario.administrador, usuario: 'admin');
      expect(s.cambiarCuentaDemo(admin: false), isFalse);
      expect(s.rol, RolUsuario.administrador);
      s.cerrar();
      s.iniciarDemo();
      s.cambiarModoDesarrollador(true);
      expect(s.cambiarCuentaDemo(admin: false), isTrue);
      expect(s.rol, RolUsuario.operador);
      expect(s.modoDesarrollador, isFalse);
      s.dispose();
    });

    testWidgets(
      'fuera de la Demo el Perfil no tiene el interruptor de cuenta',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrar(t, admin: true);
        await _abrirPerfil(t);
        expect(find.byKey(const Key('perfil-demo-admin')), findsNothing);
        expect(find.byKey(const Key('perfil-cuenta-demo')), findsNothing);
        await _cerrar(t, e);
      },
    );
  });

  group('4 · Operación real: Conexión y mini-mapa apagado', () {
    for (final bool admin in <bool>[false, true]) {
      testWidgets(
        '${admin ? 'Admin' : 'User'}: Conexión visible sin Dev Mode y mapa apagado hasta conectar',
        (WidgetTester t) async {
          final _Entorno e = await _montar(t);
          await _entrar(t, admin: admin);
          expect(e.sesion.activa, isTrue);
          expect(e.sesion.modoDesarrollador, isFalse);
          // Conexión visible de inmediato
          expect(find.byKey(const Key('boton-conexion')), findsOneWidget);
          expect(find.byKey(const Key('seccion-conexion')), findsOneWidget);
          expect(find.byType(ConexionControles), findsOneWidget);
          // Mini-mapa apagado y nada operativo
          expect(find.byKey(const Key('mapa-apagado')), findsOneWidget);
          expect(find.text(textoMapaApagado), findsOneWidget);
          expect(find.byKey(const Key('mapa-pista-lienzo')), findsNothing);
          expect(find.byKey(const Key('iniciar-recorrido')), findsNothing);
          expect(find.byKey(const Key('capa3-solicitar-pedido')), findsNothing);
          expect(e.servicio.puedeEnviarOrdenes, isFalse);
          // La hoja de Conexión también se abre desde la barra
          await _tocar(t, find.byKey(const Key('boton-conexion')));
          expect(find.text('CONEXIÓN MQTT'), findsOneWidget);
          await t.tapAt(const Offset(195, 60));
          await t.pump(const Duration(milliseconds: 400));
          // Conexión establecida: se enciende con la pista seleccionada
          e.servicio.debugMarcarConectado();
          await t.pump();
          expect(find.byKey(const Key('mapa-apagado')), findsNothing);
          final PintorPista pintor =
              t
                      .widget<CustomPaint>(
                        find.byKey(const Key('mapa-pista-lienzo')),
                      )
                      .painter!
                  as PintorPista;
          expect(pintor.trazado!.id, 'A');
          expect(find.textContaining('Pista A'), findsWidgets);
          expect(find.byKey(const Key('iniciar-recorrido')), findsOneWidget);
          expect(e.servicio.puedeEnviarOrdenes, isTrue);
          // Al desconectar vuelve a apagarse
          e.servicio.desconectar();
          await t.pump();
          expect(find.byKey(const Key('mapa-apagado')), findsOneWidget);
          expect(t.takeException(), isNull);
          await _cerrar(t, e);
        },
      );
    }
  });

  group('5 · Roles, gestión de usuarios y Modo Desarrollador', () {
    test(
      'RegistroUsuarios: Admin crea User; Admin solo con Modo Desarrollador',
      () {
        final RegistroUsuarios r = RegistroUsuarios();
        expect(
          r.crearCuenta(
            actor: RolUsuario.operador,
            rol: RolUsuario.operador,
            nombre: 'Ana',
            usuario: 'ana',
            clave: 'ana123',
          ),
          ResultadoAlta.sinPermiso,
        );
        expect(
          r.crearCuenta(
            actor: RolUsuario.administrador,
            rol: RolUsuario.operador,
            nombre: 'Ana',
            usuario: 'ana',
            clave: 'ana123',
          ),
          ResultadoAlta.creado,
        );
        expect(r.buscar('ana')!.rol, RolUsuario.operador);
        expect(
          r.crearCuenta(
            actor: RolUsuario.administrador,
            rol: RolUsuario.administrador,
            nombre: 'Beto',
            usuario: 'beto',
            clave: 'beto123',
          ),
          ResultadoAlta.requiereModoDesarrollador,
        );
        expect(r.buscar('beto'), isNull);
        expect(
          r.crearCuenta(
            actor: RolUsuario.administrador,
            rol: RolUsuario.administrador,
            nombre: 'Beto',
            usuario: 'beto',
            clave: 'beto123',
            modoDesarrollador: true,
          ),
          ResultadoAlta.creado,
        );
        expect(r.buscar('beto')!.rol, RolUsuario.administrador);
        expect(
          r.autenticar(
            'beto',
            'beto123',
            rolEsperado: RolUsuario.administrador,
          ),
          isNotNull,
        );
        r.dispose();
      },
    );

    testWidgets('User: sin gestión de usuarios ni Modo Desarrollador', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: false);
      await _abrirPerfil(t);
      expect(find.byKey(const Key('perfil-usuarios')), findsNothing);
      expect(find.byKey(const Key('perfil-modo-desarrollador')), findsNothing);
      expect(find.byKey(const Key('perfil-consolas-sensores')), findsNothing);
      expect(find.byKey(const Key('perfil-historial-datos')), findsNothing);
      await _cerrar(t, e);
    });

    testWidgets(
      'Admin sin Dev Mode crea solo User; con Dev Mode crea Admin y ve consolas e historial',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrar(t, admin: true);
        await _abrirPerfil(t);
        // Dev Mode apagado: consolas e historial ocultos
        expect(find.byKey(const Key('perfil-consolas-sensores')), findsNothing);
        expect(find.byKey(const Key('perfil-historial-datos')), findsNothing);
        await _tocar(t, find.byKey(const Key('perfil-usuarios')));
        expect(find.byType(PantallaGestionUsuarios), findsOneWidget);
        expect(find.byKey(const Key('usuarios-rol')), findsNothing);
        expect(find.text('CREAR USER'), findsOneWidget);
        await t.enterText(find.byKey(const Key('usuarios-nombre')), 'Ana');
        await t.enterText(find.byKey(const Key('usuarios-usuario')), 'ana');
        await t.enterText(find.byKey(const Key('usuarios-clave')), 'ana123');
        await _tocar(t, find.byKey(const Key('usuarios-crear')));
        expect(e.registro.buscar('ana')!.rol, RolUsuario.operador);
        await _volver(t);

        // Dev Mode encendido
        await _tocar(
          t,
          find.byKey(const Key('perfil-modo-desarrollador')),
          en: PantallaPerfil,
        );
        expect(e.sesion.modoDesarrollador, isTrue);
        await t.scrollUntilVisible(
          find.byKey(const Key('perfil-historial-datos')),
          -300,
          scrollable: _scrollDe(PantallaPerfil),
        );
        expect(
          find.byKey(const Key('perfil-consolas-sensores')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('perfil-historial-datos')), findsOneWidget);
        // Crear un Admin
        await _tocar(
          t,
          find.byKey(const Key('perfil-usuarios')),
          en: PantallaPerfil,
        );
        expect(find.byKey(const Key('usuarios-rol')), findsOneWidget);
        await _tocar(t, find.byKey(const Key('usuarios-rol-admin')));
        expect(find.text('CREAR ADMIN'), findsOneWidget);
        await t.enterText(find.byKey(const Key('usuarios-nombre')), 'Beto');
        await t.enterText(find.byKey(const Key('usuarios-usuario')), 'beto');
        await t.enterText(find.byKey(const Key('usuarios-clave')), 'beto123');
        await _tocar(t, find.byKey(const Key('usuarios-crear')));
        expect(e.registro.buscar('beto')!.rol, RolUsuario.administrador);
        expect(
          t.widget<Text>(find.byKey(const Key('usuarios-mensaje'))).data,
          'Admin @beto creado.',
        );
        await _volver(t);

        // Consolas de sensores e historial de datos
        e.servicio.iniciarSimulacion();
        e.servicio.debugEmitirPasoDemo();
        await t.pump();
        expect(e.historial.total, greaterThan(0));
        await _tocar(
          t,
          find.byKey(const Key('perfil-consolas-sensores')),
          en: PantallaPerfil,
        );
        expect(find.byKey(const Key('consola-sensores')), findsOneWidget);
        expect(find.text('EN VIVO'), findsOneWidget);
        expect(find.byKey(const Key('historial-datos')), findsOneWidget);
        expect(t.takeException(), isNull);
        e.servicio.detenerSimulacion();
        await _cerrar(t, e);
      },
    );

    testWidgets('Dev Mode añade la sección DATOS (consolas + historial)', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: true);
      e.servicio.debugMarcarConectado();
      await t.pump();
      expect(find.byType(NavigationBar), findsNothing);
      e.sesion.cambiarModoDesarrollador(true);
      await t.pump();
      await t.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('DATOS'),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('consola-sensores')), findsOneWidget);
      expect(find.byKey(const Key('historial-datos')), findsOneWidget);
      // Apagarlo los oculta de inmediato
      e.sesion.cambiarModoDesarrollador(false);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('consola-sensores')), findsNothing);
      expect(find.byKey(const Key('historial-datos')), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await _cerrar(t, e);
    });

    test('HistorialDatos registra lecturas nuevas y respeta la capacidad', () {
      final MqttService s = MqttService();
      final HistorialDatos h = HistorialDatos(s);
      const Estado e = Estado(
        numero: 7,
        modo: 'auto',
        bateria: 90,
        bateriaV: 11.8,
        ordenes: 0,
        lineaMm: 1.5,
        vIzq: 0.4,
        vDer: 0.4,
        t: 10,
      );
      for (int i = 0; i < HistorialDatos.capacidad + 5; i++) {
        h.registrar(e, null);
      }
      expect(h.total, HistorialDatos.capacidad);
      expect(h.lecturas.first.numero, 7);
      h.limpiar();
      expect(h.total, 0);
      h.dispose();
      s.dispose();
    });
  });
}
