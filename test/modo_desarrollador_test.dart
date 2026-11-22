import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:robot_ucab_app/core/demo/simulacion_pista.dart';
import 'package:robot_ucab_app/core/mqtt/mqtt_service.dart';
import 'package:robot_ucab_app/core/pistas/trazado_pista.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';
import 'package:robot_ucab_app/features/auth/catalogo_pistas.dart';
import 'package:robot_ucab_app/features/auth/escaneo_pista.dart';
import 'package:robot_ucab_app/features/auth/registro_usuarios.dart';
import 'package:robot_ucab_app/features/auth/sesion_local.dart';
import 'package:robot_ucab_app/features/perfil/aprendizaje_ruta.dart';
import 'package:robot_ucab_app/features/perfil/pantalla_perfil.dart';
import 'package:robot_ucab_app/features/telemetria/cockpit_ui.dart';
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
  _Entorno(this.servicio, this.sesion, this.catalogo);
  final MqttService servicio;
  final SesionLocal sesion;
  final CatalogoPistas catalogo;
}

/// Monta la app completa (Login → vista principal) como en `main.dart`.
Future<_Entorno> _montar(WidgetTester t) async {
  t.view.physicalSize = const Size(390 * 2, 844 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final MqttService servicio = MqttService();
  final SesionLocal sesion = SesionLocal();
  final CatalogoPistas catalogo = CatalogoPistas();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<MqttService>.value(value: servicio),
        ChangeNotifierProvider<SesionLocal>.value(value: sesion),
        ChangeNotifierProvider<CatalogoPistas>.value(value: catalogo),
        ChangeNotifierProvider<RegistroUsuarios>(
          create: (_) => RegistroUsuarios(),
        ),
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
  return _Entorno(servicio, sesion, catalogo);
}

Future<void> _cerrar(WidgetTester t, _Entorno e) async {
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpWidget(const SizedBox());
  e.servicio.dispose();
  e.sesion.dispose();
  e.catalogo.dispose();
}

Future<void> _tocar(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
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
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f);
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _entrar(WidgetTester t, {required bool admin}) async {
  if (find.byKey(const Key('login-aviso-pista')).evaluate().isNotEmpty) {
    await _tocar(t, find.byKey(const Key('login-pistas')));
    await _tocar(t, find.byKey(const Key('pista-item-A')));
  }
  await _tocar(
    t,
    find.byKey(Key(admin ? 'rol-administrador' : 'rol-operador')),
  );
  final String u = admin ? 'admin' : 'user';
  await t.enterText(find.byKey(const Key('login-usuario')), u);
  await t.enterText(find.byKey(const Key('login-clave')), u);
  await _tocar(t, find.byKey(const Key('login-entrar')));
}

/// Solo el mapa y la acción de recorrido (circuito cerrado, 0 torres); nada de
/// entregas ni controles técnicos.
void _esperaVistaLimpia() {
  expect(find.byKey(const Key('vista-limpia')), findsOneWidget);
  expect(find.byKey(const Key('mapa-pista')), findsOneWidget);
  expect(find.byKey(const Key('iniciar-recorrido')), findsOneWidget);
  expect(find.byKey(const Key('recorrido-subtitulo')), findsOneWidget);
  expect(find.text('Circuito cerrado · recorrido completo'), findsOneWidget);
  // Sin entregas ni solicitudes en pistas de 0 torres
  expect(find.byKey(const Key('nueva-solicitud')), findsNothing);
  expect(find.text('Nueva solicitud'), findsNothing);
  expect(find.byKey(const Key('confirmar-entrega')), findsNothing);
  // Controles del robot
  expect(find.byType(NavigationBar), findsNothing);
  expect(find.text('CONTROLES'), findsNothing);
  expect(find.byType(FrenoRemotoButton), findsNothing);
  expect(find.byKey(const Key('destino-lab1')), findsNothing);
  expect(find.byKey(const Key('mapa-pausa')), findsNothing);
  // Tipo / selector de conexión y telemetría avanzada
  expect(find.byKey(const Key('boton-conexion')), findsNothing);
  expect(find.text('Detalle técnico'), findsNothing);
}

void _esperaVistaTecnica() {
  expect(find.byKey(const Key('vista-limpia')), findsNothing);
  expect(find.byType(NavigationDestination), findsNWidgets(4));
  expect(find.text('CONTROLES'), findsOneWidget);
  expect(find.byType(FrenoRemotoButton), findsOneWidget);
  expect(find.byKey(const Key('boton-conexion')), findsOneWidget);
}

Future<void> _volverDelPerfil(WidgetTester t) async {
  await t.tap(find.byTooltip('Volver'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(_cargarFuentes);

  group('SesionLocal · modoDesarrollador', () {
    test(
      'arranca en false, solo el Administrador lo enciende y se reinicia',
      () {
        final SesionLocal s = SesionLocal();
        expect(s.modoDesarrollador, isFalse);
        expect(s.cambiarModoDesarrollador(true), isFalse, reason: 'sin sesión');
        s.iniciar(RolUsuario.operador, usuario: 'user');
        expect(s.cambiarModoDesarrollador(true), isFalse);
        expect(s.modoDesarrollador, isFalse);
        s.cerrar();
        s.iniciar(RolUsuario.administrador, usuario: 'admin');
        expect(s.modoDesarrollador, isFalse, reason: 'inicia siempre apagado');
        int avisos = 0;
        s.addListener(() => avisos++);
        expect(s.cambiarModoDesarrollador(true), isTrue);
        expect(s.modoDesarrollador, isTrue);
        expect(avisos, 1, reason: 'es reactivo');
        s.cerrar();
        expect(s.modoDesarrollador, isFalse);
        s.iniciar(RolUsuario.administrador, usuario: 'admin');
        expect(s.modoDesarrollador, isFalse, reason: 'se reinicia al cerrar');
        s.dispose();
      },
    );
  });

  group('Vista limpia por defecto', () {
    testWidgets('Operador: solo mapa + realizar envío', (WidgetTester t) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: false);
      expect(e.sesion.rol, RolUsuario.operador);
      _esperaVistaLimpia();
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    testWidgets('Administrador sin Modo Desarrollador: solo mapa + envío', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: true);
      expect(e.sesion.rol, RolUsuario.administrador);
      expect(e.sesion.modoDesarrollador, isFalse);
      _esperaVistaLimpia();
      expect(t.takeException(), isNull);
      await _cerrar(t, e);
    });

    testWidgets(
      'Iniciar recorrido en circuito cerrado (0 torres) arranca vuelta completa sin entregas',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrar(t, admin: false);
        expect(find.byKey(const Key('nueva-solicitud')), findsNothing);
        await t.tap(find.byKey(const Key('iniciar-recorrido')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(e.servicio.simulando, isTrue);
        expect(e.servicio.pista!.modoVueltaCompleta, isTrue);
        expect(e.servicio.pista!.vueltaEnCurso, isTrue);
        // Al completar la vuelta simulada vuelve al inicio y se detiene
        e.servicio.pista!.avanzar(40);
        await t.pump(const Duration(milliseconds: 200));
        expect(e.servicio.pista!.vueltaCompletada, isTrue);
        expect(e.servicio.pista!.posicionM, closeTo(0.0, 0.05));
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );

    testWidgets(
      'pista con >= 1 torre (Entrega a laboratorio) sí muestra Nueva solicitud',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        final PistaLocal p = e.catalogo.agregarPista(
          nombre: 'Pista con Torre',
          longitudM: 9.0,
          torresControl: 1,
        )!;
        e.catalogo.completarEscaneo(
          p.id,
          MetricasPista(
            largoM: 9.0,
            puntosControlM: puntosControlPara(9.0),
            segmentosValidados: const <bool>[true, true, true],
          ),
        );
        await t.pump(const Duration(milliseconds: 100));
        await _entrar(t, admin: false);
        expect(find.byKey(const Key('iniciar-recorrido')), findsNothing);
        expect(find.byKey(const Key('nueva-solicitud')), findsOneWidget);
        await t.tap(find.byKey(const Key('nueva-solicitud')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('enviar-solicitud')), findsOneWidget);
        await _cerrar(t, e);
      },
    );
  });

  group('Interruptor Modo Desarrollador', () {
    testWidgets('el Operador no lo tiene en su Perfil', (WidgetTester t) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: false);
      await _tocar(t, find.byKey(const Key('boton-perfil')));
      expect(find.text('PERFIL · OPERADOR'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byKey(const Key('perfil-cerrar')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(PantallaPerfil),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const Key('perfil-cerrar')), findsOneWidget);
      expect(find.byKey(const Key('perfil-modo-desarrollador')), findsNothing);
      expect(find.text('Modo Desarrollador'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      await _cerrar(t, e);
    });

    testWidgets(
      'en el Administrador está justo debajo de "Cerrar Sesión", en la esquina inferior',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrar(t, admin: true);
        await _tocar(t, find.byKey(const Key('boton-perfil')));
        final Finder interruptor = find.byKey(
          const Key('perfil-modo-desarrollador'),
        );
        await t.scrollUntilVisible(
          interruptor,
          300,
          scrollable: find
              .descendant(
                of: find.byType(PantallaPerfil),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(interruptor, findsOneWidget);
        expect(t.widget<Switch>(interruptor).value, isFalse);
        final Rect cerrar = t.getRect(find.byKey(const Key('perfil-cerrar')));
        final Rect fila = t.getRect(
          find.byKey(const Key('perfil-modo-desarrollador-fila')),
        );
        // Debajo de Cerrar Sesión, pegado a él y alineado a la derecha
        expect(fila.top, greaterThanOrEqualTo(cerrar.bottom - 0.5));
        expect(fila.top - cerrar.bottom, lessThan(16));
        expect(fila.right, closeTo(cerrar.right, 1));
        expect(fila.width, lessThan(cerrar.width * 0.8));
        // Es lo último del Perfil
        final Finder lista = find
            .descendant(
              of: find.byType(PantallaPerfil),
              matching: find.byType(Scrollable),
            )
            .first;
        final ScrollableState sc = t.state<ScrollableState>(lista);
        expect(sc.position.pixels, closeTo(sc.position.maxScrollExtent, 1));
        await _cerrar(t, e);
      },
    );

    testWidgets(
      'encenderlo muestra controles y conexión; apagarlo o cerrar sesión los oculta',
      (WidgetTester t) async {
        final _Entorno e = await _montar(t);
        await _entrar(t, admin: true);
        _esperaVistaLimpia();

        // Encender desde el Perfil
        await _tocar(t, find.byKey(const Key('boton-perfil')));
        await _tocar(t, find.byKey(const Key('perfil-modo-desarrollador')));
        expect(e.sesion.modoDesarrollador, isTrue);
        await _volverDelPerfil(t);
        _esperaVistaTecnica();
        // Controles del robot accesibles
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('CONTROLES'),
          ),
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('CONTROLES'), findsWidgets);
        // Tipo de conexión accesible
        await t.tap(find.byKey(const Key('boton-conexion')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('CONEXIÓN MQTT'), findsOneWidget);
        await t.tapAt(const Offset(195, 60)); // cierra la hoja
        await t.pump(const Duration(milliseconds: 400));

        // Apagar: vuelve de inmediato a mapa + envío
        await _tocar(t, find.byKey(const Key('boton-perfil')));
        await _tocar(t, find.byKey(const Key('perfil-modo-desarrollador')));
        expect(e.sesion.modoDesarrollador, isFalse);
        await _volverDelPerfil(t);
        _esperaVistaLimpia();

        // Encender otra vez y cerrar sesión: al volver a entrar está apagado
        await _tocar(t, find.byKey(const Key('boton-perfil')));
        await _tocar(t, find.byKey(const Key('perfil-modo-desarrollador')));
        expect(e.sesion.modoDesarrollador, isTrue);
        await _tocar(t, find.byKey(const Key('perfil-cerrar')));
        expect(e.sesion.activa, isFalse);
        expect(e.sesion.modoDesarrollador, isFalse);
        await _entrar(t, admin: true);
        expect(e.sesion.modoDesarrollador, isFalse);
        _esperaVistaLimpia();
        expect(t.takeException(), isNull);
        await _cerrar(t, e);
      },
    );
  });

  group('Pistas y estaciones = specs/pista_canonica.json', () {
    final Map<String, dynamic> spec = jsonDecode(
      File('../specs/pista_canonica.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final double largo = (spec['longitudTotalM'] as num).toDouble();
    final List<double> pcs = <double>[
      for (final dynamic p in spec['puntosDeControl'] as List<dynamic>)
        ((p as Map<String, dynamic>)['posicionM'] as num).toDouble(),
    ];
    final List<double> limites = <double>[
      0,
      for (final dynamic tr in spec['tramos'] as List<dynamic>)
        ((tr as Map<String, dynamic>)['hastaM'] as num).toDouble(),
    ];

    test('largo, PC1–PC3 y tramos T1–T4 coinciden con la especificación', () {
      expect(largo, largoCanonicoM);
      expect(pcs, <double>[3.0, 4.5, 7.5]);
      expect(puntosControlCanonicosM, pcs);
      expect(limitesTramosCanonicosM, limites);
      expect(puntosControlPara(largo), pcs);
    });

    test('trazado canónico de SIM1/SIM2: 9,000 m, cerrado y T2 recto', () {
      final TrazadoPista b = TrazadoPista.canonica();
      expect(b.largoM, closeTo(largo, 0.006));
      expect(
        (b.puntosM.first - b.puntosM.last).distance,
        lessThan(0.01),
        reason: 'circuito cerrado',
      );
      // Igual que SIM2 (pistas_radar.test.js): el tramo sin línea 3,0–4,5 es recto
      expect(b.radioMinimoEntre(pcs[0], pcs[1]), greaterThan(10));
      // Recta larga de 3,6 m y curvas de 0,27 m de radio (pista.js · B_GEO)
      expect(b.radioMinimoEntre(0, largo), closeTo(0.27, 0.02));
    });

    test(
      'Pista A: circuito histórico de 8,05 m con sus estaciones escaladas',
      () {
        final TrazadoPista a = TrazadoPista.historicaA();
        expect(a.largoM, closeTo(8.05, 0.006));
        expect(TrazadoPista.paraPista('A', 8.05).id, 'A');
        final CatalogoPistas c = CatalogoPistas();
        final PistaLocal pa = c.porId('A')!;
        expect(pa.longitudM, largoPistaAM);
        expect(pa.metricas!.puntosControlM, puntosControlPara(8.05));
        expect(pa.metricas!.puntosControlM, <double>[2.68, 4.03, 6.71]);
        c.dispose();
      },
    );

    test('Modo Demo y mapa: estaciones 0,0 / 3,0 / 7,5 m (sin 3,78 ni 6,3)', () {
      final SimulacionPista s = SimulacionPista();
      expect(s.longitudM, largo);
      expect(s.posiciones[DestinoPista.cuartoComponentes], 0.0);
      expect(s.posiciones[DestinoPista.puntoControl], pcs[0]);
      expect(s.posiciones[DestinoPista.laboratorio1], pcs[2]);
      expect(s.posiciones.values, isNot(contains(3.78)));
      expect(s.posiciones.values, isNot(contains(6.3)));
      expect(fraccionDeDestino(DestinoPista.puntoControl), pcs[0] / largo);
      expect(fraccionDeDestino(DestinoPista.laboratorio1), pcs[2] / largo);
      expect(fraccionPc2, pcs[1] / largo);
      expect(
        textoEstaciones(largo),
        'Cuarto 0,0 · PC1 3,0 · PC2 4,5 · PC3 / Lab. 1 7,5 · cierre 9,0 m',
      );
      // El mapa dibuja el trazado real: PC1 y PC2 caen en la misma recta larga
      final PistaGeometria g = PistaGeometria(const Size(358, 308));
      expect(g.trazado.id, 'B');
      final Offset p1 = g.puntoEn(pcs[0] / largo);
      final Offset p2 = g.puntoEn(pcs[1] / largo);
      expect((p1.dy - p2.dy).abs(), lessThan(0.5));
      // La Pista A simulada mide 8,05 m y escala sus estaciones
      final SimulacionPista sa = SimulacionPista(longitudM: 8.05);
      expect(sa.posiciones[DestinoPista.laboratorio1], 6.71);
    });

    test(
      'Escaneo de una pista de 9,0 m fija PC1–PC3 equitativos (L/3) y 3 lecturas por segmento',
      () {
        final EscaneoPista cerrada = EscaneoPista(
          pistaId: 'P1',
          largoEstimadoM: 9.0,
          geometria: TipoGeometriaPista.circuitoCerrado,
        );
        cerrada.completarTodo();
        expect(cerrada.distanciaVerificada, isTrue);
        expect(cerrada.metricas!.largoM, closeTo(largo, 0.01));
        expect(cerrada.metricas!.puntosControlM, <double>[3.0, 6.0, 9.0]);
        expect(cerrada.metricas!.lecturasPorSegmento, <int>[3, 3, 3]);
        expect(cerrada.totalLecturasCompletadas, 9);
        expect(cerrada.metricas!.giroTotalGrados, 360);
        cerrada.dispose();

        final EscaneoPista lineal = EscaneoPista(
          pistaId: 'P2',
          largoEstimadoM: 9.0,
          geometria: TipoGeometriaPista.lineal,
        );
        lineal.completarTodo();
        expect(lineal.metricas!.puntosControlM, <double>[3.0, 6.0, 9.0]);
        expect(lineal.metricas!.lecturasPorSegmento, <int>[3, 3, 3]);
        expect(lineal.metricas!.giroTotalGrados, 0);
        lineal.dispose();

        final TrazadoPista trLin = TrazadoPista.paraPista(
          'P2',
          9.0,
          geometria: TipoGeometriaPista.lineal,
        );
        expect(trLin.cerrada, isFalse);
        expect(trLin.largoM, closeTo(9.0, 0.01));
      },
    );

    testWidgets('el mapa principal muestra las estaciones de la pista activa', (
      WidgetTester t,
    ) async {
      final _Entorno e = await _montar(t);
      await _entrar(t, admin: false);
      expect(
        t.widget<Text>(find.byKey(const Key('mapa-estaciones'))).data,
        textoEstaciones(8.05),
      );
      final CustomPaint lienzo = t.widget<CustomPaint>(
        find.byKey(const Key('mapa-pista-lienzo')),
      );
      expect((lienzo.painter! as PintorPista).trazado!.id, 'A');
      await _cerrar(t, e);
    });
  });
}
