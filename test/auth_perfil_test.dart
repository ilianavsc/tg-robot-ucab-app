import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:robot_ucab_app/core/mqtt/mqtt_service.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';
import 'package:robot_ucab_app/features/auth/catalogo_pistas.dart';
import 'package:robot_ucab_app/features/auth/escaneo_pista.dart';
import 'package:robot_ucab_app/features/auth/pantalla_login.dart';
import 'package:robot_ucab_app/features/auth/registro_usuarios.dart';
import 'package:robot_ucab_app/features/auth/sesion_local.dart';
import 'package:robot_ucab_app/features/perfil/aprendizaje_ruta.dart';
import 'package:robot_ucab_app/features/perfil/pantalla_perfil.dart';
import 'package:robot_ucab_app/features/telemetria/mapa_pista.dart';
import 'package:robot_ucab_app/main.dart' show PuertaAcceso;
import 'package:robot_ucab_app/shared/widgets/pastilla_mqtt.dart';

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
  _Entorno(this.servicio, this.sesion, this.registro, this.catalogo);
  final MqttService servicio;
  final SesionLocal sesion;
  final RegistroUsuarios registro;
  final CatalogoPistas catalogo;
}

/// Monta la app desde la puerta de acceso (Login o Telemetría según la sesión).
Future<_Entorno> _montar(
  WidgetTester t, {
  double ancho = 390,
  double alto = 844,
}) async {
  t.view.physicalSize = Size(ancho * 2, alto * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final MqttService servicio = MqttService();
  final SesionLocal sesion = SesionLocal();
  final RegistroUsuarios registro = RegistroUsuarios();
  final CatalogoPistas catalogo = CatalogoPistas();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MqttService>.value(value: servicio),
        ChangeNotifierProvider<SesionLocal>.value(value: sesion),
        ChangeNotifierProvider<RegistroUsuarios>.value(value: registro),
        ChangeNotifierProvider<CatalogoPistas>.value(value: catalogo),
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
  return _Entorno(servicio, sesion, registro, catalogo);
}

Future<void> _cerrar(WidgetTester t, _Entorno e) async {
  await t.pump(const Duration(milliseconds: 400)); // ACK simulado del demo
  await t.pumpWidget(const SizedBox());
  e.servicio.dispose();
  e.sesion.dispose();
  e.registro.dispose();
  e.catalogo.dispose();
}

/// Desplaza la lista del Perfil hasta que [f] esté construido y a la vista.
Future<void> _mostrar(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    300,
    scrollable: find
        .descendant(
          of: find.byType(PantallaPerfil),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) await _mostrar(t, f);
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f);
  await t.pump(); // arranca la transición de ruta o de la hoja
  await t.pump(const Duration(milliseconds: 400));
}

/// Despliega la tarjeta colapsable del Login si aún está plegada.
Future<void> _abrirLogin(WidgetTester t) async {
  if (find.byKey(const Key('login-usuario')).evaluate().isEmpty) {
    await _tocar(t, find.byKey(const Key('login-abrir')));
  }
}

/// Abre el Login, selecciona Pista A si no hay pista activa, elige rol,
/// escribe credenciales y pulsa "Iniciar Sesión".
Future<void> _entrarCon(
  WidgetTester t,
  String usuario,
  String clave, {
  bool admin = false,
}) async {
  await _abrirLogin(t);
  if (find.byKey(const Key('login-aviso-pista')).evaluate().isNotEmpty) {
    await _tocar(t, find.byKey(const Key('login-pistas')));
    await _tocar(t, find.byKey(const Key('pista-item-A')));
  }
  await _tocar(
    t,
    find.byKey(Key(admin ? 'rol-administrador' : 'rol-operador')),
  );
  await t.enterText(find.byKey(const Key('login-usuario')), usuario);
  await t.enterText(find.byKey(const Key('login-clave')), clave);
  await _tocar(t, find.byKey(const Key('login-entrar')));
}

Future<void> _abrirPerfil(WidgetTester t) async {
  await _tocar(t, find.byKey(const Key('boton-perfil')));
}

void main() {
  setUpAll(_cargarFuentes);

  group('SesionLocal (mock)', () {
    test('empieza sin sesión y guarda rol, usuario, nombre y modo demo', () {
      final SesionLocal s = SesionLocal();
      expect(s.activa, isFalse);
      expect(s.rol, isNull);
      s.iniciar(
        RolUsuario.administrador,
        usuario: '  admin ',
        nombre: ' Administrador demo ',
        ahora: DateTime(2026, 11, 19, 10),
      );
      expect(s.activa, isTrue);
      expect(s.rol, RolUsuario.administrador);
      expect(s.usuario, 'admin');
      expect(s.nombre, 'Administrador demo');
      expect(s.demo, isFalse);
      expect(
        s.duracion(DateTime(2026, 11, 19, 10, 42, 5)),
        const Duration(minutes: 42, seconds: 5),
      );
      s.cerrar();
      expect(s.activa, isFalse);
      expect(s.usuario, '');
      expect(s.nombre, '');
      expect(s.duracion(), Duration.zero);
    });

    test('notifica solo cuando cambia', () {
      final SesionLocal s = SesionLocal();
      int n = 0;
      s.addListener(() => n++);
      s.cerrar(); // ya estaba cerrada
      expect(n, 0);
      s.iniciar(RolUsuario.operador, usuario: 'a');
      s.cerrar();
      expect(n, 2);
    });

    test('formatoDuracion', () {
      expect(formatoDuracion(const Duration(hours: 3, minutes: 42)), '03h 42m');
      expect(
        formatoDuracion(const Duration(minutes: 5, seconds: 9)),
        '05m 09s',
      );
      expect(formatoDuracion(Duration.zero), '00m 00s');
    });
  });

  group('estado MQTT real', () {
    test('desconectado muestra "--" y el demo se rotula como demo', () {
      final MqttService s = MqttService();
      expect(resumenMqtt(s).texto, 'MQTT: Desconectado (--)');
      s.iniciarSimulacion();
      expect(resumenMqtt(s).texto, 'MQTT: Demo (sin red)');
      s.detenerSimulacion();
      s.dispose();
    });
  });

  group('Login', () {
    testWidgets(
      'inicio: solo 3 botones (Pistas, Login colapsable, Demo) y Pista A predeterminada',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        expect(find.text('Autonomous Laboratory AGV'), findsOneWidget);
        // Exactamente 3 botones principales
        expect(find.byType(BotonInicio), findsNWidgets(3));
        expect(find.byKey(const Key('login-pistas')), findsOneWidget);
        expect(find.byKey(const Key('login-abrir')), findsOneWidget);
        expect(find.byKey(const Key('login-demo')), findsOneWidget);
        expect(find.text('Pistas'), findsOneWidget);
        expect(find.text('Login'), findsOneWidget);
        expect(find.text('Demo'), findsOneWidget);
        // Pista A ya viene seleccionada
        expect(e.catalogo.activaId, 'A');
        expect(find.textContaining('Pista A'), findsOneWidget);
        // Tarjeta de Login plegada: sin formulario ni nada de MQTT
        expect(find.byKey(const Key('login-tarjeta')), findsNothing);
        expect(find.byKey(const Key('login-usuario')), findsNothing);
        expect(find.textContaining('MQTT'), findsNothing);
        expect(find.byType(PastillaMqtt), findsNothing);
        expect(find.byKey(const Key('login-acceso-rapido')), findsNothing);
        // Desplegar: aparece el formulario con la pista de ingreso
        await _tocar(t, find.byKey(const Key('login-abrir')));
        expect(find.byKey(const Key('login-tarjeta')), findsOneWidget);
        expect(find.byKey(const Key('login-selector-rol')), findsOneWidget);
        expect(find.byKey(const Key('rol-operador')), findsOneWidget);
        expect(find.byKey(const Key('rol-administrador')), findsOneWidget);
        expect(find.text('User'), findsOneWidget);
        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('USUARIO'), findsOneWidget);
        expect(find.text('CONTRASEÑA'), findsOneWidget);
        expect(find.text('Iniciar Sesión'), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const Key('login-pista-activa'))).data,
          startsWith('Ingresando a: Pista A'),
        );
        // Placeholder dinámico según rol
        TextField campoUsuario() =>
            t.widget<TextField>(find.byKey(const Key('login-usuario')));
        expect(campoUsuario().decoration!.hintText, 'user');
        await _tocar(t, find.byKey(const Key('rol-administrador')));
        expect(campoUsuario().decoration!.hintText, 'admin');
        await _tocar(t, find.byKey(const Key('rol-operador')));
        expect(campoUsuario().decoration!.hintText, 'user');
        // Sin registro público
        expect(find.textContaining('Registrarse'), findsNothing);
        expect(find.textContaining('Crear cuenta'), findsNothing);
        // Plegar de nuevo
        await _tocar(t, find.byKey(const Key('login-abrir')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('login-usuario')), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets('user / user entra como Operador (cuenta 01)', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrarCon(t, 'user', 'user');
      expect(e.sesion.rol, RolUsuario.operador);
      expect(e.sesion.usuario, 'user');
      expect(e.sesion.demo, isFalse);
      expect(e.servicio.simulando, isFalse);
      // Vista limpia por defecto: mapa + realizar envío, sin pestañas técnicas
      expect(find.byKey(const Key('vista-limpia')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await _cerrar(t, e);
    });

    testWidgets(
      'admin / admin entra como Administrador (cuenta 00, sin distinguir mayúsculas)',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrarCon(
          t,
          '  ADMIN ',
          'admin',
          admin: true,
        );
        expect(e.sesion.rol, RolUsuario.administrador);
        expect(e.sesion.usuario, 'admin');
        await _cerrar(t, e);
      },
    );

    testWidgets('el selector deslizante valida que el rol coincida con la cuenta', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      // Cuenta administrador con selector en Operador -> rechazada
      await _entrarCon(t, 'admin', 'admin', admin: false);
      expect(e.sesion.activa, isFalse);
      expect(
        find.text('Esta cuenta corresponde al perfil Administrador.'),
        findsOneWidget,
      );
      // Cuenta usuario con selector en Administrador -> rechazada
      await _entrarCon(t, 'user', 'user', admin: true);
      expect(e.sesion.activa, isFalse);
      expect(
        find.text('Esta cuenta corresponde al perfil Usuario.'),
        findsOneWidget,
      );
      await _cerrar(t, e);
    });

    testWidgets('credenciales incorrectas no inician sesión', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      for (final (String u, String c, bool adm) in <(String, String, bool)>[
        ('admin', 'Admin', true), // distingue mayúsculas
        ('admin', '', true),
        ('admin', 'user', true),
        ('', '', false),
        ('nadie', 'nadie', false),
      ]) {
        await _entrarCon(t, u, c, admin: adm);
        expect(e.sesion.activa, isFalse, reason: '$u / $c');
        expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
      }
      await _cerrar(t, e);
    });

    testWidgets('el ojo muestra y oculta la contraseña', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _abrirLogin(t);
      TextField clave() =>
          t.widget<TextField>(find.byKey(const Key('login-clave')));
      expect(clave().obscureText, isTrue);
      await _tocar(t, find.byTooltip('Mostrar contraseña'));
      expect(clave().obscureText, isFalse);
      await _cerrar(t, e);
    });

    testWidgets(
      'Demo entra como Admin (Demo) sobre la Pista C y arranca la simulación',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-demo')));
        expect(e.servicio.simulando, isTrue);
        expect(e.sesion.rol, RolUsuario.administrador);
        expect(e.sesion.nombre, 'Admin (Demo)');
        expect(e.sesion.demo, isTrue);
        expect(e.catalogo.activaId, 'C');
        expect(e.servicio.pista!.longitudM, largoPistaCM);
        expect(
          find.text('MODO DEMO · datos simulados, sin red ni robot'),
          findsOneWidget,
        );
        await _cerrar(t, e);
      },
    );

    testWidgets('no desborda en pantalla pequeña (360×640)', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t, ancho: 360, alto: 640);
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    test('CatalogoPistas inicia con Pista A configurada; una pista nueva nace básica (0 torres) y pendiente', () {
      final CatalogoPistas c = CatalogoPistas();
      expect(c.pistas.map((PistaLocal p) => p.id), <String>['A']);
      // Pista A viene predeterminada
      expect(c.activaId, 'A');
      expect(c.tienePistaActiva, isTrue);
      expect(c.activaConfigurada, isTrue);
      expect(c.seleccionar('B'), isFalse);
      expect(c.seleccionar('A'), isTrue);
      expect(c.activaId, 'A');
      expect(c.activaConfigurada, isTrue);
      final PistaLocal a = c.activa!;
      expect(a.estado, EstadoPista.configurada);
      expect(a.torresControl, 0);
      expect(a.tipoViaje, TipoViajePista.circuitoCerrado);
      expect(a.esCircuitoCerrado, isTrue);
      expect(a.metricas!.completa, isTrue);
      expect(a.metricas!.puntosControlM.length, 3);
      expect(a.metricas!.segmentosValidados, <bool>[true, true, true]);
      final PistaLocal? basica = c.agregarPista(
        nombre: 'Laboratorio 2',
        longitudM: 12.5,
      );
      expect(basica, isNotNull);
      expect(basica!.torresControl, 0);
      expect(basica.tipoViaje, TipoViajePista.circuitoCerrado);
      expect(basica.esCircuitoCerrado, isTrue);
      expect(basica.estado, EstadoPista.pendiente);
      expect(basica.configurada, isFalse);
      expect(basica.metricas, isNull);
      final PistaLocal? conTorre = c.agregarPista(
        nombre: 'Laboratorio Torre 1',
        longitudM: 9.0,
        torresControl: 1,
      );
      expect(conTorre, isNotNull);
      expect(conTorre!.torresControl, 1);
      expect(conTorre.tipoViaje, TipoViajePista.entregaLaboratorio);
      expect(conTorre.esCircuitoCerrado, isFalse);
      expect(c.activa!.nombre, 'Laboratorio Torre 1');
      expect(c.activaConfigurada, isFalse);
      expect(c.pistas.length, 3);
      expect(c.agregarPista(nombre: '  ', longitudM: 5), isNull);
      c.dispose();
    });

    test('puedeIniciarSesion: Operador exige configurada; Admin entra con cualquier activa', () {
      final CatalogoPistas c = CatalogoPistas();
      // Pista A (predeterminada y configurada): ambos pueden.
      expect(c.puedeIniciarSesion(RolUsuario.operador), isTrue);
      expect(c.puedeIniciarSesion(RolUsuario.administrador), isTrue);
      // Pista nueva (pendiente): solo el Administrador.
      c.agregarPista(nombre: 'Lab 2', longitudM: 12.5);
      expect(c.puedeIniciarSesion(RolUsuario.operador), isFalse);
      expect(c.puedeIniciarSesion(RolUsuario.administrador), isTrue);
      // Sin pista seleccionada: nadie puede entrar.
      c.eliminarPista(c.activaId!);
      c.eliminarPista('A');
      expect(c.tienePistaActiva, isFalse);
      expect(c.puedeIniciarSesion(RolUsuario.operador), isFalse);
      expect(c.puedeIniciarSesion(RolUsuario.administrador), isFalse);
      c.dispose();
    });

    testWidgets(
      'sin pista seleccionada se bloquea el login (User y Admin) con aviso; con Pista A el User entra',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        // El gestor de pistas lista la Pista A (activa)
        await _tocar(t, find.byKey(const Key('login-pistas')));
        expect(find.byKey(const Key('pistas-hoja')), findsOneWidget);
        expect(find.byKey(const Key('pista-item-A')), findsOneWidget);
        expect(find.byKey(const Key('pista-tipo-A')), findsOneWidget);
        expect(find.text('Circuito cerrado'), findsOneWidget);
        expect(find.byKey(const Key('pista-item-B')), findsNothing);
        expect(find.byKey(const Key('pista-pendiente-A')), findsNothing);
        expect(find.byKey(const Key('pista-nueva')), findsOneWidget);
        // Se quita la selección eliminando la única pista
        await _tocar(t, find.byKey(const Key('pista-eliminar-A')));
        await _tocar(t, find.byKey(const Key('pista-eliminar-confirmar')));
        expect(e.catalogo.tienePistaActiva, isFalse);
        expect(find.text('Sin pista seleccionada'), findsOneWidget);
        await _abrirLogin(t);
        expect(find.byKey(const Key('login-aviso-pista')), findsOneWidget);
        expect(find.text(avisoSinPista), findsOneWidget);
        for (final (String u, bool adm) in <(String, bool)>[
          ('user', false),
          ('admin', true),
        ]) {
          await _tocar(
            t,
            find.byKey(Key(adm ? 'rol-administrador' : 'rol-operador')),
          );
          await t.enterText(find.byKey(const Key('login-usuario')), u);
          await t.enterText(find.byKey(const Key('login-clave')), u);
          await _tocar(t, find.byKey(const Key('login-entrar')));
          expect(e.sesion.activa, isFalse, reason: u);
          // El aviso se repite como error del formulario
          expect(find.text(avisoSinPista), findsNWidgets(2));
        }
        // Con una pista seleccionada el login funciona
        e.catalogo.agregarPista(nombre: 'Pista Z', longitudM: 5);
        e.catalogo.completarEscaneo(
          e.catalogo.activaId!,
          MetricasPista(
            largoM: 5,
            puntosControlM: puntosControlEquitativos(5),
            segmentosValidados: const <bool>[true, true, true],
          ),
        );
        await t.pump();
        expect(find.byKey(const Key('login-pista-activa')), findsOneWidget);
        await _entrarCon(t, 'user', 'user');
        expect(e.sesion.activa, isTrue);
        expect(e.sesion.rol, RolUsuario.operador);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets('seleccionar una pista desde Pistas la deja activa en el estado', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      e.catalogo.agregarPista(nombre: 'Pista B', longitudM: 9);
      await t.pump();
      expect(e.catalogo.activaId, 'P1');
      await _tocar(t, find.byKey(const Key('login-pistas')));
      await _tocar(t, find.byKey(const Key('pista-item-A')));
      expect(e.catalogo.activaId, 'A');
      expect(find.text('Activa: Pista A · Circuito histórico'), findsOneWidget);
      expect(find.byKey(const Key('pistas-hoja')), findsNothing);
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    testWidgets(
      '+ Nueva pista nace pendiente y bloquea al Operador hasta completar el escaneo',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-pistas')));
        await _tocar(t, find.byKey(const Key('pista-nueva')));
        // Modo básico: sin selector de torres
        expect(
          find.byKey(const Key('nueva-pista-modo-basico')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('nueva-pista-torres')), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        await t.enterText(
          find.byKey(const Key('nueva-pista-nombre')),
          'Pasillo Norte',
        );
        await t.enterText(find.byKey(const Key('nueva-pista-largo')), '11.5');
        await _tocar(t, find.byKey(const Key('nueva-pista-crear')));
        // Se abre el Escaneo y Validación de Pista; lo abandonamos a medias
        expect(find.byKey(const Key('escaneo-lienzo')), findsOneWidget);
        expect(find.text('Pasillo Norte'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 500));
        await _tocar(t, find.byKey(const Key('escaneo-salir')));
        // De vuelta en Login: pista pendiente, User bloqueado
        await _abrirLogin(t);
        expect(find.byKey(const Key('login-aviso-pendiente')), findsOneWidget);
        expect(
          find.byKey(const Key('login-continuar-escaneo')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('login-pista-activa')), findsNothing);
        // Un User no puede entrar con la pista pendiente
        await _entrarCon(t, 'user', 'user');
        expect(e.sesion.activa, isFalse);
        expect(find.textContaining('pendiente de escaneo: un User'), findsOneWidget);
        await _tocar(t, find.byKey(const Key('login-pistas')));
        expect(find.byKey(const Key('pista-pendiente-P1')), findsOneWidget);
        await t.tapAt(const Offset(20, 20)); // cierra la hoja de pistas
        await t.pump(const Duration(milliseconds: 400));
        expect(e.sesion.activa, isFalse);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets(
      'escaneo completo (Lectura lenta → Pasada normal → Viajes 1/3, 2/3, 3/3) configura la pista y habilita el login',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-pistas')));
        await _tocar(t, find.byKey(const Key('pista-nueva')));
        await t.enterText(
          find.byKey(const Key('nueva-pista-nombre')),
          'Laboratorio 2',
        );
        await t.enterText(find.byKey(const Key('nueva-pista-largo')), '6.0');
        await _tocar(t, find.byKey(const Key('nueva-pista-crear')));
        expect(find.byKey(const Key('escaneo-lienzo')), findsOneWidget);
        expect(find.text('PENDIENTE · EN ESCANEO'), findsOneWidget);
        final List<String> vistas = <String>[];
        String etapaActiva() {
          for (final EtapaEscaneo et in EtapaEscaneo.values) {
            final Finder f = find.byKey(Key('etapa-${et.name}-estado'));
            if (f.evaluate().isEmpty) continue;
            final String txt = t.widget<Text>(f).data!;
            if (txt.endsWith('%')) return et.name;
          }
          return 'fin';
        }

        for (int i = 0; i < 600; i++) {
          if (find.byKey(const Key('escaneo-listo')).evaluate().isNotEmpty) {
            break;
          }
          final String et = etapaActiva();
          if (et != 'fin' && (vistas.isEmpty || vistas.last != et)) {
            vistas.add(et);
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(vistas, <String>[
          'lecturaLenta',
          'pasadaNormal',
          'viaje1',
          'viaje2',
          'viaje3',
        ]);
        expect(find.byKey(const Key('escaneo-listo')), findsOneWidget);
        expect(find.text('CONFIGURADA'), findsOneWidget);
        expect(find.text('3/3'), findsOneWidget);
        expect(find.text('3/3 · 3/3 · 3/3 (9/9)'), findsOneWidget);
        // sin auto-avance por temporizador: el usuario confirma el regreso
        await _tocar(t, find.byKey(const Key('escaneo-listo')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('escaneo-lienzo')), findsNothing);
        await _abrirLogin(t);
        expect(find.byKey(const Key('login-aviso-pendiente')), findsNothing);
        expect(find.byKey(const Key('login-pista-activa')), findsOneWidget);
        expect(find.textContaining('Ingresando a: Laboratorio 2'), findsOneWidget);
        await _entrarCon(t, 'user', 'user');
        expect(e.sesion.activa, isTrue);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets(
      '+ Nueva pista permite elegir Lineal (Pista B), escanea con checkpoints L/3 y 3 lecturas/segmento y dibuja mapa lineal',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _tocar(t, find.byKey(const Key('login-pistas')));
        await _tocar(t, find.byKey(const Key('pista-nueva')));
        expect(find.byKey(const Key('nueva-pista-tipo')), findsOneWidget);
        await _tocar(t, find.byKey(const Key('tipo-pista-lineal')));
        await t.enterText(
          find.byKey(const Key('nueva-pista-nombre')),
          'Pista B',
        );
        await t.enterText(find.byKey(const Key('nueva-pista-largo')), '9.0');
        await _tocar(t, find.byKey(const Key('nueva-pista-crear')));

        // Verifica que la pista nació Lineal, aviso Admin sin obstáculos y escanea todas las etapas
        expect(e.catalogo.activa!.geometria, TipoGeometriaPista.lineal);
        expect(find.byKey(const Key('escaneo-aviso-admin')), findsOneWidget);
        expect(
          find.text('Calibración guiada por Administrador'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('escaneo-lienzo')), findsOneWidget);
        expect(find.text('Lineal'), findsOneWidget);

        for (int i = 0; i < 600; i++) {
          if (find.byKey(const Key('escaneo-listo')).evaluate().isNotEmpty) {
            break;
          }
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const Key('escaneo-listo')), findsOneWidget);
        expect(find.text('3,00 m · 6,00 m · 9,00 m'), findsOneWidget);
        expect(find.text('3/3 · 3/3 · 3/3 (9/9)'), findsOneWidget);
        expect(e.catalogo.activa!.configurada, isTrue);
        expect(
          e.catalogo.activa!.metricas!.puntosControlM,
          <double>[3.0, 6.0, 9.0],
        );

        // Vuelve al Login y entra como Operador (user/user)
        await _tocar(t, find.byKey(const Key('escaneo-listo')));
        await _entrarCon(t, 'user', 'user');
        expect(e.sesion.activa, isTrue);
        // Operación real: el mini-mapa se enciende al establecer la conexión
        expect(find.byKey(const Key('mapa-apagado')), findsOneWidget);
        e.servicio.debugMarcarConectado();
        await t.pump();

        // El mapa principal dibuja la ruta lineal con checkpoints equitativos
        final CustomPaint lienzo = t.widget<CustomPaint>(
          find.byKey(const Key('mapa-pista-lienzo')),
        );
        final PintorPista pintor = lienzo.painter! as PintorPista;
        expect(pintor.trazado!.cerrada, isFalse);
        expect(pintor.mostrarCheckpointsP05, isTrue);
        expect(
          t.widget<Text>(find.byKey(const Key('mapa-estaciones'))).data,
          'Inicio 0,0 · PC1 3,0 · PC2 6,0 · PC3 9,0 m',
        );
        expect(find.text('Pista lineal · recorrido completo'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    test(
      'CatalogoPistas.eliminarPista remueve la pista y limpia la activa si coincidía',
      () {
        final CatalogoPistas c = CatalogoPistas();
        expect(c.seleccionar('A'), isTrue);
        expect(c.tienePistaActiva, isTrue);
        expect(c.eliminarPista('inexistente'), isFalse);
        expect(c.eliminarPista('A'), isTrue);
        expect(c.pistas, isEmpty);
        expect(c.activa, isNull);
        expect(c.tienePistaActiva, isFalse);
        c.dispose();
      },
    );

    testWidgets(
      'eliminar una pista desde Pistas la remueve y bloquea el login si era la activa',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        // Abre Pistas y pulsa papelera de Pista A -> diálogo de confirmación
        await _tocar(t, find.byKey(const Key('login-pistas')));
        await _tocar(t, find.byKey(const Key('pista-eliminar-A')));
        expect(
          find.text('¿Eliminar pista Pista A · Circuito histórico?'),
          findsOneWidget,
        );
        await _tocar(t, find.byKey(const Key('pista-eliminar-confirmar')));
        // Pista eliminada, selección limpia y login bloqueado
        await _abrirLogin(t);
        expect(find.byKey(const Key('login-aviso-pista')), findsOneWidget);
        await t.enterText(find.byKey(const Key('login-usuario')), 'user');
        await t.enterText(find.byKey(const Key('login-clave')), 'user');
        await _tocar(t, find.byKey(const Key('login-entrar')));
        expect(e.sesion.activa, isFalse);
        await _tocar(t, find.byKey(const Key('login-pistas')));
        expect(find.byKey(const Key('pista-item-A')), findsNothing);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );
  });

  group('Perfil · Operador', () {
    testWidgets('el botón de Perfil de la barra abre la vista del Operador', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrarCon(t, 'user', 'user');
      // Vista limpia: sin las pestañas técnicas
      expect(find.byType(NavigationDestination), findsNothing);
      await _abrirPerfil(t);
      expect(find.text('PERFIL · USER'), findsOneWidget);
      expect(find.text('@user'), findsOneWidget);
      expect(find.text('Usuario'), findsWidgets);
      expect(find.byKey(const Key('perfil-cerrar')), findsOneWidget);
      // Sin información de tipo de conexión ni telemetría técnica para Operador
      expect(find.text('SESIÓN ACTUAL'), findsNothing);
      expect(find.text('ENLACE MQTT'), findsNothing);
      expect(find.textContaining('MQTT'), findsNothing);
      expect(find.textContaining('Broker'), findsNothing);
      expect(find.textContaining('Wi-Fi'), findsNothing);
      expect(find.textContaining('BLE'), findsNothing);
      expect(find.byKey(const Key('perfil-broker')), findsNothing);
      expect(find.byKey(const Key('perfil-latencia')), findsNothing);
      // Solo Admin: Fail-Safe, gestión de usuarios y CSV
      expect(find.byKey(const Key('perfil-failsafe')), findsNothing);
      expect(find.text('Gestión de Usuarios'), findsNothing);
      expect(find.byKey(const Key('perfil-exportar')), findsNothing);
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    testWidgets('Cerrar Sesión vuelve al Login', (WidgetTester t) async {
      final _Entorno e = await _montar(t);
      await _entrarCon(t, 'user', 'user');
      await _abrirPerfil(t);
      await _tocar(t, find.byKey(const Key('perfil-cerrar')));
      await t.pump(const Duration(milliseconds: 400)); // termina el pop
      expect(e.sesion.activa, isFalse);
      expect(find.byKey(const Key('login-abrir')), findsOneWidget);
      expect(find.byType(PantallaPerfil), findsNothing);
      await _cerrar(t, e);
    });

    testWidgets('Cerrar Sesión desde el Modo Demo detiene la simulación', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _tocar(t, find.byKey(const Key('login-demo')));
      await _abrirPerfil(t);
      // Datos del demo: paquetes reales de la analítica P12
      expect(e.servicio.analitica.totalPaquetes, greaterThan(0));
      await _tocar(t, find.byKey(const Key('perfil-cerrar')));
      expect(e.servicio.simulando, isFalse);
      expect(e.sesion.activa, isFalse);
      expect(find.byKey(const Key('login-demo')), findsOneWidget);
      // La Pista C de la Demo se retira y vuelve la Pista A
      expect(e.catalogo.porId('C'), isNull);
      expect(e.catalogo.activaId, 'A');
      await _cerrar(t, e);
    });
  });

  group('Perfil · Administrador', () {
    Future<_Entorno> entrarAdmin(
      WidgetTester t, {
      double ancho = 390,
      bool modoDev = true,
    }) async {
      final _Entorno e = await _montar(t, ancho: ancho);
      await _entrarCon(t, 'admin', 'admin', admin: true);
      await _abrirPerfil(t);
      if (modoDev) {
        await _tocar(t, find.byKey(const Key('perfil-modo-desarrollador')));
      }
      return e;
    }

    testWidgets(
      'sin Modo Desarrollador oculta Fail-Safe, Aprendizaje y Analítica P12; al activarlo aparecen',
      (WidgetTester t) async {
        final _Entorno e = await entrarAdmin(t, modoDev: false);
        expect(find.text('PERFIL · ADMIN'), findsOneWidget);
        expect(find.text('@admin'), findsOneWidget);
        expect(find.byKey(const Key('perfil-usuarios')), findsOneWidget);
        expect(find.byKey(const Key('perfil-cerrar')), findsOneWidget);
        expect(
          find.byKey(const Key('perfil-modo-desarrollador')),
          findsOneWidget,
        );
        // Ocultos con modoDesarrollador == false (incluye tipo de conexión)
        expect(find.byKey(const Key('perfil-failsafe')), findsNothing);
        expect(find.byKey(const Key('perfil-aprendizaje')), findsNothing);
        expect(find.text('ANALÍTICA DE SESIÓN (P12)'), findsNothing);
        expect(find.byKey(const Key('perfil-exportar')), findsNothing);
        expect(find.text('ENLACE MQTT'), findsNothing);
        expect(find.text('SESIÓN ACTUAL'), findsNothing);
        expect(find.textContaining('MQTT'), findsNothing);
        expect(find.byKey(const Key('perfil-broker')), findsNothing);
        expect(find.byKey(const Key('perfil-latencia')), findsNothing);
        // Al activar Modo Desarrollador vuelven a aparecer
        await _tocar(t, find.byKey(const Key('perfil-modo-desarrollador')));
        expect(e.sesion.modoDesarrollador, isTrue);
        expect(find.byKey(const Key('perfil-failsafe')), findsOneWidget);
        expect(find.byKey(const Key('perfil-aprendizaje')), findsOneWidget);
        expect(find.byKey(const Key('perfil-usuarios')), findsOneWidget);
        await _mostrar(t, find.byKey(const Key('perfil-exportar')));
        expect(find.text('ANALÍTICA DE SESIÓN (P12)'), findsOneWidget);
        await _mostrar(t, find.byKey(const Key('perfil-broker')));
        expect(find.text('ENLACE MQTT'), findsOneWidget);
        expect(find.byKey(const Key('perfil-latencia')), findsOneWidget);
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets('Fail-Safe es de solo lectura, con candado y umbrales reales', (
      WidgetTester t,
    ) async {
      final _Entorno e = await entrarAdmin(t);
      expect(find.text('PERFIL · ADMIN'), findsOneWidget);
      final Finder tarjeta = find.byKey(const Key('perfil-failsafe'));
      expect(tarjeta, findsOneWidget);
      expect(
        find.descendant(of: tarjeta, matching: find.byIcon(Icons.lock_outline)),
        findsWidgets,
      );
      expect(find.text('Parada crítica frontal'), findsOneWidget);
      expect(find.text('Zona de precaución'), findsOneWidget);
      expect(find.text('< 20 cm'), findsOneWidget);
      expect(find.text('20–50 cm'), findsOneWidget);
      expect(find.textContaining('Solo lectura'), findsWidgets);
      // Ningún control editable dentro de la tarjeta
      for (final Type tipo in <Type>[
        TextField,
        Switch,
        Slider,
        Checkbox,
        Radio<int>,
        IconButton,
        TextButton,
        ElevatedButton,
        OutlinedButton,
        FilledButton,
        InkWell,
      ]) {
        expect(
          find.descendant(of: tarjeta, matching: find.byType(tipo)),
          findsNothing,
          reason: '$tipo no debe existir en la tarjeta Fail-Safe',
        );
      }
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    testWidgets('Exportar Sesión (CSV) usa el reporte real de P12', (
      WidgetTester t,
    ) async {
      String? copiado;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall c) async {
          if (c.method == 'Clipboard.setData') {
            copiado = (c.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final _Entorno e = await entrarAdmin(t);

      // Sin datos de sesión: botón deshabilitado y aviso
      final Finder boton = find.byKey(const Key('perfil-exportar'));
      await _mostrar(t, boton);
      expect(t.widget<OutlinedButton>(boton).onPressed, isNull);
      expect(find.textContaining('Sin datos de sesión'), findsOneWidget);

      // Con datos (Modo Demo): se habilita y exporta el CSV de P12
      e.servicio.iniciarSimulacion();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<OutlinedButton>(boton).onPressed, isNotNull);
      await _tocar(t, boton);
      expect(copiado, isNotNull);
      expect(copiado, startsWith('# Reporte de sesion'));
      expect(copiado, contains('paquetes_total;'));
      expect(copiado, contains('origen;Modo Demo;'));
      await _cerrar(t, e);
    });

    for (final (String n, double w) in <(String, double)>[
      ('360', 360),
      ('1100', 1100),
    ]) {
      testWidgets('la vista de Admin no desborda ($n px)', (
        WidgetTester t,
      ) async {
        final _Entorno e = await entrarAdmin(t, ancho: w);
        e.servicio.iniciarSimulacion();
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      });
    }
  });

  testWidgets('la barra de app con el botón de Perfil no desborda a 360 px', (
    WidgetTester t,
  ) async {
    final _Entorno e = await _montar(t, ancho: 360, alto: 740);
    await _tocar(t, find.byKey(const Key('login-demo')));
    expect(find.byKey(const Key('boton-perfil')), findsOneWidget);
    expect(
      find.byTooltip('Perfil'),
      findsNothing,
    ); // sin tooltip nativo: usa Semantics
    expect(t.takeException(), isNull);
    await _cerrar(t, e);
  });
}
