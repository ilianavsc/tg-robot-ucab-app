import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ucab_app/core/config/brokers.dart';
import 'package:robot_ucab_app/core/contracts/generated/robot_contract.dart';
import 'package:robot_ucab_app/core/pistas/trazado_pista.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';

void main() {
  group('Contrato MQTT y Pista (v2.0.0 · offline)', () {
    test('1. versión 2.0.0, schemaVersion y sourceCommit 9e01afd en source-lock', () {
      final Map<String, dynamic> lock =
          jsonDecode(
                File('lib/core/contracts/source-lock.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(lock['sourceRepo'], 'ilianavsc/tg-robot-ucab-portfolio');
      expect(lock['sourceCommit'], '9e01afdcb2db95dde5773f8096b4275112effeda');
      expect(lock['contractVersion'], '2.0.0');
      expect(lock['schemaVersion'], '2.0.0');
      expect(RobotMqttContract.version, '2.0.0');
      expect(RobotMqttContract.schemaVersion, '2.0.0');
      expect(
        RegExp(r'^[0-9a-f]{40}$').hasMatch(lock['sourceCommit'] as String),
        isTrue,
      );
    });

    test('2. tópicos base, brokers (HiveMQ → EMQX → Mosquitto) y separación HIL vs P04', () {
      expect(RobotMqttContract.topicoEstado, 'ucab-tg-sf/robot/estado');
      expect(
        RobotMqttContract.topicoUltrasonido,
        'ucab-tg-sf/robot/ultrasonido',
      );
      expect(RobotMqttContract.topicoOrdenes, 'ucab-tg-sf/robot/ordenes');
      expect(RobotMqttContract.topicoAck, 'ucab-tg-sf/robot/ordenes/ack');
      expect(RobotMqttContract.topicoAlertas, 'ucab-tg-sf/robot/alertas');
      expect(RobotMqttContract.topicoConexion, 'ucab-tg-sf/robot/conexion');
      expect(RobotMqttContract.topicosMeta['conexion']!.retained, isTrue);
      expect(RobotMqttContract.qosEstado, 0);
      expect(RobotMqttContract.qosOrdenes, 1);
      expect(RobotMqttContract.qosAlertas, 2);
      expect(RobotMqttContract.ackTimeoutMs, 5000);
      expect(RobotMqttContract.comandosValidos, <String>[
        'adelante',
        'atras',
        'izquierda',
        'derecha',
        'frenar',
        'auto',
      ]);
      for (final String campo
          in RobotMqttContract.camposEstadoExclusivosSimuladorP04) {
        expect(
          RobotMqttContract.camposEstadoFisicoHIL.contains(campo),
          isFalse,
        );
      }
      expect(
        brokers.map((BrokerEndpoint b) => b.nombre).toList(),
        <String>['HiveMQ', 'EMQX', 'Mosquitto'],
      );
    });

    test('3. los 7 tópicos nuevos de Capa 3/MPU-6050 con qos, retained y direccion', () {
      expect(RobotMqttContract.topicosMeta.length, 13);
      expect(RobotMqttContract.topicosCapa3.length, 7);

      final Map<String, ({String ruta, int qos, bool retained, String dir})>
      esperados =
          <String, ({String ruta, int qos, bool retained, String dir})>{
            'rutas_estado': (
              ruta: 'ucab-tg-sf/robot/rutas/estado',
              qos: 1,
              retained: true,
              dir: 'robot->app',
            ),
            'rutas_escaneo': (
              ruta: 'ucab-tg-sf/robot/rutas/escaneo',
              qos: 1,
              retained: false,
              dir: 'app->robot',
            ),
            'rutas_reposicionamiento': (
              ruta: 'ucab-tg-sf/robot/rutas/reposicionamiento',
              qos: 1,
              retained: false,
              dir: 'app->robot',
            ),
            'pedidos_solicitud': (
              ruta: 'ucab-tg-sf/robot/pedidos/solicitud',
              qos: 1,
              retained: false,
              dir: 'app->robot',
            ),
            'pedidos_estado': (
              ruta: 'ucab-tg-sf/robot/pedidos/estado',
              qos: 1,
              retained: true,
              dir: 'robot->app',
            ),
            'pedidos_cancelacion': (
              ruta: 'ucab-tg-sf/robot/pedidos/cancelacion',
              qos: 1,
              retained: false,
              dir: 'app->robot',
            ),
            'sensores_inercial': (
              ruta: 'ucab-tg-sf/robot/sensores/inercial',
              qos: 0,
              retained: false,
              dir: 'robot->app',
            ),
          };

      for (final MapEntry<
            String,
            ({String ruta, int qos, bool retained, String dir})
          >
          e
          in esperados.entries) {
        final MqttTopicMeta meta = RobotMqttContract.topicosMeta[e.key]!;
        expect(meta.ruta, e.value.ruta, reason: e.key);
        expect(meta.qos, e.value.qos, reason: e.key);
        expect(meta.retained, e.value.retained, reason: e.key);
        expect(meta.direccion, e.value.dir, reason: e.key);
      }
    });

    test('4. enums de Capa 3 (10 rutas, 5 pedidos, 3 alertas MPU-6050 y bloqueo)', () {
      expect(RobotMqttContract.estadosRuta, <String>[
        'SIN_RUTA',
        'ESCANEO_IDA',
        'ESPERA_REPOSICION',
        'ESCANEO_RETORNO',
        'OPERACION_BUCLE',
        'REESCANEO_PARADA',
        'OPERACION_CON_PARADA',
        'PAUSA_OBSTACULO',
        'ERROR_SEGURIDAD',
        'RECUPERACION_MANUAL',
      ]);
      expect(RobotMqttContract.estadosPedido, <String>[
        'SIN_PEDIDO',
        'SOLICITADO',
        'EN_TRANSITO',
        'CANCELACION_SEGURA',
        'ENTREGADO',
      ]);
      expect(RobotMqttContract.alertasMpu6050, <String>[
        'impacto',
        'inclinacion',
        'atascamiento',
      ]);
      expect(RobotMqttContract.movimientoBloqueadoEnEstados, <String>[
        'ESPERA_REPOSICION',
        'ERROR_SEGURIDAD',
        'RECUPERACION_MANUAL',
      ]);
      expect(RobotMqttContract.camposSensoresInercial, <String>[
        'pitch',
        'roll',
        'acel_g',
        'alerta',
        'timestamp',
        'schema_version',
      ]);
    });

    test('5. metadatos de trazabilidad y deduplicación para comandos/eventos Capa 3', () {
      expect(RobotMqttContract.trazabilidadCamposObligatorios, <String>[
        'message_id',
        'request_id',
        'sequence',
        'timestamp',
        'schema_version',
      ]);
      expect(
        RobotMqttContract.trazabilidadDeduplicacion,
        contains('message_id'),
      );
      expect(
        RobotMqttContract.trazabilidadDeduplicacion,
        contains('request_id'),
      );
    });

    test('6. fixture pista_canonica.json (rssiLlegadaDbm sin typo y geometría)', () {
      final Map<String, dynamic> spec =
          jsonDecode(
                File('test/fixtures/pista_canonica.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        (spec['longitudTotalM'] as num).toDouble(),
        RobotTrackContract.longitudCanonicaM,
      );
      expect(largoCanonicoM, RobotTrackContract.longitudCanonicaM);
      expect(
        puntosControlCanonicosM,
        RobotTrackContract.puntosControlFuncionalesCanonicosM,
      );
      expect(
        RobotTrackContract.terciosEquitativosPistaAM,
        <double>[2.68, 5.37, 8.05],
      );
      expect(
        RobotTrackContract.terciosEquitativosPistaBM,
        <double>[3.0, 6.0, 9.0],
      );
      final Map<String, dynamic> umbrales =
          spec['umbrales'] as Map<String, dynamic>;
      expect(umbrales['rssiLlegadaDbm'], RobotTrackContract.rssiLlegadaDbm);
      expect(umbrales.containsKey('rssiLlegadadBm'), isFalse);
    });
  });

  group('Sistema de Diseño Oscuro (cockpit_theme.dart)', () {
    test('tokens de superficie, acento, radios y tabular-nums alineados', () {
      expect(CockpitColors.surface, const Color(0xFF10141A));
      expect(CockpitColors.surfaceLow, const Color(0xFF181C22));
      expect(CockpitColors.onSurface, const Color(0xFFDFE2EB));
      expect(CockpitColors.primary, const Color(0xFF00F2FE));
      expect(CockpitColors.borderSubtle, const Color(0x14FFFFFF));
      expect(CockpitRadius.sm, 4);
      expect(CockpitRadius.md, 8);
      expect(CockpitRadius.lg, 12);
      expect(CockpitRadius.xl, 16);
      expect(CockpitRadius.touchMin, 44);
      expect(CockpitText.telemetryLg.fontFeatures, CockpitText.tabular);
      expect(CockpitText.telemetryMd.fontFeatures, CockpitText.tabular);
      expect(CockpitText.labelMd.fontFeatures, CockpitText.tabular);
    });
  });
}
