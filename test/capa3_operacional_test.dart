import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:robot_ucab_app/core/contracts/generated/robot_contract.dart';
import 'package:robot_ucab_app/core/mqtt/mqtt_service.dart';
import 'package:robot_ucab_app/core/operacion/capa3_operacional.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';
import 'package:robot_ucab_app/features/auth/catalogo_pistas.dart';
import 'package:robot_ucab_app/features/auth/pantalla_escaneo_pista.dart';
import 'package:robot_ucab_app/features/telemetria/pantalla_dashboard.dart';
import 'package:robot_ucab_app/features/telemetria/solicitud_activa.dart';

void main() {
  group('Capa 3 — Máquina de Rutas y Pedidos (controlador puro)', () {
    test('Ruta Cerrada sin parada: 3 usos completados habilitan reescaneo y fallidos no suman', () {
      final Capa3OperacionalController c = Capa3OperacionalController(
        tipoRuta: TipoRutaOperacional.cerrada,
        largoM: 9.0,
      );
      expect(c.duracionEstimadaEscaneoS, closeTo(21.95, 0.02));
      expect(c.iniciarEscaneo().ok, isTrue);
      expect(c.completarPasadaIda().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.operacionBucle);
      expect(c.puedeSolicitarPedido, isFalse);
      expect(c.solicitarPedido(paradaId: 'P1').ok, isFalse);

      // Fallido no incrementa
      expect(c.registrarUsoCompletado(exitoso: false), 0);
      expect(c.puedeReescanearParada, isFalse);

      expect(c.registrarUsoCompletado(exitoso: true), 1);
      expect(c.registrarUsoCompletado(exitoso: true), 2);
      expect(c.puedeReescanearParada, isFalse);
      expect(c.iniciarReescaneoParada('Estación A').ok, isFalse);

      expect(c.registrarUsoCompletado(exitoso: true), 3);
      expect(c.puedeReescanearParada, isTrue);
      expect(c.iniciarReescaneoParada('Estación A').ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.reescaneoParada);
      expect(c.completarReescaneoParada().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.operacionConParada);
      expect(c.puedeSolicitarPedido, isTrue);
    });

    test('Ruta Lineal: parada obligatoria, doble escaneo y sin auto-retorno por timeout en ESPERA_REPOSICION', () {
      final Capa3OperacionalController c = Capa3OperacionalController(
        tipoRuta: TipoRutaOperacional.lineal,
        largoM: 9.0,
      );
      expect(c.duracionEstimadaEscaneoS, closeTo(43.90, 0.05));
      expect(c.iniciarEscaneo().ok, isFalse);

      expect(c.configurarParada('PC3 / Estación 1'), isTrue);
      expect(c.iniciarEscaneo().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.escaneoIda);

      // Escala de reloj 4x acelera tiempo sim sin afectar el real
      c.setEscalaReloj(4);
      c.avanzarReloj(2.0);
      expect(c.tiempoRealS, closeTo(2.0, 0.01));
      expect(c.tiempoSimS, closeTo(8.0, 0.01));

      expect(c.completarPasadaIda().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.esperaReposicion);
      expect(c.puedeMover, isFalse);

      // Jamás auto-retorna tras 3600 s
      c.avanzarReloj(3600.0);
      expect(c.estadoRuta, EstadoRutaOperacional.esperaReposicion);

      expect(c.confirmarReposicionamiento().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.escaneoRetorno);
      expect(c.completarPasadaRetorno().ok, isTrue);
      expect(c.estadoRuta, EstadoRutaOperacional.operacionConParada);
      expect(c.rutaAprendida?.dobleEscaneo, isTrue);
      expect(c.puedeSolicitarPedido, isTrue);
    });

    test('CANCELACION_SEGURA preserva la ruta aprendida sin reiniciar escaneo', () {
      final Capa3OperacionalController c = Capa3OperacionalController(
        tipoRuta: TipoRutaOperacional.lineal,
        largoM: 9.0,
        paradaConfigurada: true,
        paradaNombre: 'Estación 1',
      );
      c.iniciarEscaneo();
      c.completarPasadaIda();
      c.confirmarReposicionamiento();
      c.completarPasadaRetorno();
      final RutaAprendidaOperacional? aprendidaAntes = c.rutaAprendida;
      expect(aprendidaAntes, isNotNull);

      expect(c.solicitarPedido(paradaId: 'Estación 1').ok, isTrue);
      expect(c.despacharPedido().ok, isTrue);
      expect(c.estadoPedido, EstadoPedidoOperacional.enTransito);

      expect(c.cancelarPedidoSeguro().ok, isTrue);
      expect(c.estadoPedido, EstadoPedidoOperacional.cancelacionSegura);
      expect(c.rutaAprendida, same(aprendidaAntes));
      expect(c.estadoRuta, EstadoRutaOperacional.operacionConParada);

      expect(c.confirmarDetencionCancelacion(), isTrue);
      expect(c.estadoPedido, EstadoPedidoOperacional.sinPedido);
      expect(c.rutaAprendida, same(aprendidaAntes));
    });
  });

  group('Capa 3 — MqttService (bloqueo, trazabilidad, MPU-6050 y anti-obsoletos)', () {
    test('bloquea órdenes de movimiento en ESPERA_REPOSICION, ERROR_SEGURIDAD y RECUPERACION_MANUAL', () {
      final MqttService svc = MqttService();
      svc.iniciarSimulacion();
      addTearDown(svc.dispose);

      // 1. ESPERA_REPOSICION
      svc.configurarTipoRutaCapa3(TipoRutaOperacional.lineal);
      svc.configurarParadaCapa3('Estación 1');
      svc.iniciarEscaneoCapa3();
      svc.completarPasadaIdaCapa3();
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.esperaReposicion);
      expect(svc.publicarOrden('adelante'), isFalse);
      expect(svc.publicarOrden('frenar'), isTrue);

      // 2. ERROR_SEGURIDAD por MPU-6050
      svc.dispararAlertaMpuDemo(AlertaMpu6050.impacto);
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.errorSeguridad);
      expect(svc.publicarOrden('auto'), isFalse);
      expect(svc.publicarOrden('frenar'), isTrue);

      // 3. RECUPERACION_MANUAL
      expect(svc.iniciarRecuperacionManualCapa3(), isTrue);
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.recuperacionManual);
      expect(svc.publicarOrden('adelante'), isFalse);

      // 4. Reanudar libera movimiento
      expect(svc.completarRecuperacionManualCapa3(), isTrue);
      expect(svc.publicarOrden('adelante'), isTrue);
    });

    test('sobre de trazabilidad (message_id, request_id, sequence, timestamp, schema_version) y descarte de retained obsoletos', () {
      final MqttService svc = MqttService();
      svc.iniciarSimulacion();
      addTearDown(svc.dispose);

      final ResultadoCapa3 r = svc.solicitarPedidoCapa3(paradaId: 'PC3 / Estación 1');
      expect(r.ok, isTrue);
      final Map<String, dynamic>? payload = svc.ultimoPayloadCapa3;
      expect(svc.ultimoTopicoCapa3, RobotMqttContract.topicoPedidosSolicitud);
      expect(payload, isNotNull);
      expect(payload!['message_id'], isA<String>());
      expect(payload['request_id'], isA<String>());
      expect(payload['sequence'], 1);
      expect(payload['timestamp'], isA<int>());
      expect(payload['schema_version'], RobotMqttContract.schemaVersion);

      // Cancelar incrementa sequence de forma monótona
      expect(svc.cancelarPedidoSeguroCapa3().ok, isTrue);
      expect(svc.ultimoTopicoCapa3, RobotMqttContract.topicoPedidosCancelacion);
      expect(svc.ultimoPayloadCapa3!['sequence'], 2);

      // Mensajes retained: descarta obsoletos por timestamp
      svc.debugProcesarRutasEstado(jsonEncode(<String, dynamic>{
        'estado_ruta': 'OPERACION_BUCLE',
        'tipo_ruta': 'cerrada',
        'parada_configurada': false,
        'usos_completados': 2,
        'timestamp': 2000,
      }));
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.operacionBucle);
      expect(svc.capa3.usosCompletados, 2);

      // Retained obsoleto (timestamp 1500 < 2000) se ignora
      svc.debugProcesarRutasEstado(jsonEncode(<String, dynamic>{
        'estado_ruta': 'SIN_RUTA',
        'usos_completados': 0,
        'timestamp': 1500,
      }));
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.operacionBucle);
      expect(svc.capa3.usosCompletados, 2);

      // Alerta QoS 2 MPU-6050 fuerza ERROR_SEGURIDAD
      svc.debugProcesarAlertaMpu(jsonEncode(<String, dynamic>{
        'alerta': 'inclinacion',
        'valor': 35.0,
        'timestamp': 3000,
      }));
      expect(svc.capa3.estadoRuta, EstadoRutaOperacional.errorSeguridad);
      expect(svc.capa3.alertaMpu, AlertaMpu6050.inclinacion);
    });
  });

  group('Capa 3 — UI (PantallaEscaneoPista y PantallaDashboard)', () {
    testWidgets('PantallaEscaneoPista valida parada lineal, reloj 1x/2x/4x y confirmación manual de reposicionamiento', (WidgetTester tester) async {
      final CatalogoPistas catalogo = CatalogoPistas();
      final PistaLocal p = catalogo.agregarPista(
        nombre: 'Pista QA',
        longitudM: 9.0,
        geometria: TipoGeometriaPista.circuitoCerrado,
      )!;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildCockpitTheme(),
          home: PantallaEscaneoPista(
            catalogo: catalogo,
            pistaId: p.id,
            velocidadReproduccion: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('escaneo-panel-capa3')), findsOneWidget);
      expect(find.byKey(const Key('escaneo-tiempos-capa3')), findsOneWidget);

      // Cambiar a Ruta Lineal sin parada dispara validación
      await tester.tap(find.byKey(const Key('escaneo-tipo-lineal')));
      await tester.pump();
      expect(
        find.textContaining('Parada obligatoria en Ruta Lineal'),
        findsOneWidget,
      );

      // Ingresar parada y cambiar reloj a 2x
      await tester.enterText(
        find.byKey(const Key('escaneo-parada-input')),
        'Estación Sur',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('escaneo-reloj-2x')));
      await tester.pump();

      // Re-seleccionar lineal ahora que ya tiene parada -> entra en ESCANEO_IDA
      await tester.tap(find.byKey(const Key('escaneo-tipo-lineal')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('escaneo-fin-ida')));
      await tester.pump();

      // Aparece botón manual "Confirmar reposicionamiento"
      expect(
        find.byKey(const Key('escaneo-confirmar-reposicion')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('escaneo-confirmar-reposicion')));
      await tester.pump();
      expect(find.text('ESCANEO_RETORNO'), findsOneWidget);
    });

    testWidgets('PantallaDashboard en vista Operador (390x844 y 1280x840): pedidos, cancelación segura, MPU-6050 y 0 jerga MQTT', (WidgetTester tester) async {
      final MqttService svc = MqttService();
      svc.iniciarSimulacion();
      addTearDown(svc.dispose);

      for (final Size vp in const <Size>[Size(390, 844), Size(1280, 840)]) {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MqttService>.value(value: svc),
              ChangeNotifierProvider<SolicitudActiva>(
                create: (_) => SolicitudActiva(),
              ),
              ChangeNotifierProvider<CatalogoPistas>(
                create: (_) => CatalogoPistas(),
              ),
            ],
            child: MaterialApp(
              theme: buildCockpitTheme(),
              home: const Scaffold(body: PantallaDashboard(tecnico: false)),
            ),
          ),
        );
        await tester.pump();

        // Vista Operador libre de jerga técnica
        expect(find.textContaining('MQTT'), findsNothing);
        expect(find.byKey(const Key('tarjeta-capa3')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // Flujo Solicitar -> Cancelar (CANCELACION_SEGURA) -> Confirmar
      await tester.scrollUntilVisible(
        find.byKey(const Key('capa3-solicitar-pedido')),
        200,
      );
      await tester.tap(find.byKey(const Key('capa3-solicitar-pedido')));
      await tester.pump();
      expect(svc.capa3.estadoPedido, EstadoPedidoOperacional.enTransito);

      await tester.tap(find.byKey(const Key('capa3-cancelar-pedido')));
      await tester.pump();
      expect(svc.capa3.estadoPedido, EstadoPedidoOperacional.cancelacionSegura);
      expect(svc.capa3.rutaAprendida, isNotNull);

      await tester.tap(find.byKey(const Key('capa3-confirmar-cancelacion')));
      await tester.pump();
      expect(svc.capa3.estadoPedido, EstadoPedidoOperacional.sinPedido);

      // Flujo MPU-6050 -> Banner -> Recuperación manual
      await tester.scrollUntilVisible(
        find.byKey(const Key('capa3-demo-impacto')),
        200,
      );
      await tester.tap(find.byKey(const Key('capa3-demo-impacto')));
      await tester.pump();
      expect(find.byKey(const Key('capa3-banner-mpu')), findsOneWidget);

      await tester.tap(find.byKey(const Key('capa3-iniciar-recuperacion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('capa3-completar-recuperacion')));
      await tester.pump();
      expect(find.byKey(const Key('capa3-banner-mpu')), findsNothing);
      svc.detenerSimulacion();
    });
  });
}
