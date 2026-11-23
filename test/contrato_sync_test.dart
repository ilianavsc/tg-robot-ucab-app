import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ucab_app/core/config/brokers.dart';
import 'package:robot_ucab_app/core/contracts/generated/robot_contract.dart';
import 'package:robot_ucab_app/core/pistas/trazado_pista.dart';
import 'package:robot_ucab_app/core/theme/cockpit_theme.dart';

void main() {
  group('Contrato MQTT y Pista generado (offline)', () {
    test('source-lock.json registra el SHA del repo portafolio', () {
      final Map<String, dynamic> lock =
          jsonDecode(
                File('lib/core/contracts/source-lock.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(lock['sourceRepo'], 'ilianavsc/tg-robot-ucab-portfolio');
      expect(lock['contractVersion'], RobotMqttContract.version);
      expect(
        RegExp(r'^[0-9a-f]{40}$').hasMatch(lock['sourceCommit'] as String),
        isTrue,
      );
    });

    test('tópicos, QoS, comandos y separación HIL vs P04 coinciden', () {
      expect(RobotMqttContract.topicoEstado, 'ucab-tg-sf/robot/estado');
      expect(
        RobotMqttContract.topicoUltrasonido,
        'ucab-tg-sf/robot/ultrasonido',
      );
      expect(RobotMqttContract.topicoOrdenes, 'ucab-tg-sf/robot/ordenes');
      expect(RobotMqttContract.topicoAck, 'ucab-tg-sf/robot/ordenes/ack');
      expect(RobotMqttContract.topicoAlertas, 'ucab-tg-sf/robot/alertas');
      expect(RobotMqttContract.topicoConexion, 'ucab-tg-sf/robot/conexion');
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

    test('geometría de pista y tercios L/3 coinciden con fixture', () {
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
