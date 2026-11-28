import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:robot_ucab_app/core/contracts/generated/robot_contract.dart';
import 'package:robot_ucab_app/core/mqtt/mqtt_service.dart';
import 'package:robot_ucab_app/features/telemetria/pantalla_controles.dart';

void main() {
  group('MqttService · timeout de ACK (RobotMqttContract.ackTimeoutMs)', () {
    testWidgets(
      'tras 5 s sin ACK libera esperandoAck y expone resultado desconocido',
      (WidgetTester tester) async {
        final MqttService servicio = MqttService();
        addTearDown(servicio.dispose);

        servicio.debugRegistrarOrdenPendiente('adelante');
        expect(servicio.esperandoAck, isTrue);
        expect(servicio.ackExpirado, isFalse);
        expect(servicio.estadoAck, 'esperando ACK');

        // Antes del límite (4999 ms), sigue esperando confirmación.
        await tester.pump(
          const Duration(milliseconds: RobotMqttContract.ackTimeoutMs - 1),
        );
        expect(servicio.esperandoAck, isTrue);
        expect(servicio.ackExpirado, isFalse);

        // Al cumplirse exactamente 5000 ms, se libera la espera.
        await tester.pump(const Duration(milliseconds: 1));
        expect(servicio.esperandoAck, isFalse);
        expect(servicio.ackExpirado, isTrue);
        expect(servicio.estadoAck, 'resultado desconocido');
        expect(servicio.ultimoError, contains('resultado desconocido'));
      },
    );

    testWidgets(
      'si el ACK llega antes de 5 s cancela el timer y marca la orden confirmada',
      (WidgetTester tester) async {
        final MqttService servicio = MqttService();
        addTearDown(servicio.dispose);

        final String id = servicio.debugRegistrarOrdenPendiente('frenar');
        expect(servicio.esperandoAck, isTrue);

        await tester.pump(const Duration(milliseconds: 1200));
        servicio.debugProcesarAck('{"id":"$id","recibidas":1,"t":1200}');

        expect(servicio.esperandoAck, isFalse);
        expect(servicio.ackExpirado, isFalse);
        expect(servicio.estadoAck, 'confirmada');

        // Avanzar más allá del timeout no debe marcarla expirada.
        await tester.pump(
          const Duration(milliseconds: RobotMqttContract.ackTimeoutMs),
        );
        expect(servicio.ackExpirado, isFalse);
        expect(servicio.estadoAck, 'confirmada');
      },
    );

    testWidgets(
      'dispose() cancela el timer de ACK sin dejar temporizadores pendientes',
      (WidgetTester tester) async {
        final MqttService servicio = MqttService();
        servicio.debugRegistrarOrdenPendiente('izquierda');
        expect(servicio.esperandoAck, isTrue);

        servicio.dispose();

        // Si el timer no se hubiera cancelado, FakeAsync fallaría al cerrar el test.
        await tester.pump(
          const Duration(milliseconds: RobotMqttContract.ackTimeoutMs),
        );
      },
    );

    testWidgets(
      'PantallaControles muestra aviso claro de resultado desconocido cuando expira el ACK',
      (WidgetTester tester) async {
        final MqttService servicio = MqttService();
        addTearDown(servicio.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<MqttService>.value(
            value: servicio,
            child: const MaterialApp(home: Scaffold(body: PantallaControles())),
          ),
        );

        servicio.debugRegistrarOrdenPendiente('adelante');
        await tester.pump();
        expect(find.text('ESPERANDO'), findsOneWidget);

        await tester.pump(
          const Duration(milliseconds: RobotMqttContract.ackTimeoutMs),
        );
        expect(find.text('SIN ACK'), findsOneWidget);
        expect(find.textContaining('resultado desconocido'), findsWidgets);
      },
    );
  });
}
