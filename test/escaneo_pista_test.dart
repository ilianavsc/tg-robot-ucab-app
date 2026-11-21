import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ucab_app/features/auth/catalogo_pistas.dart';
import 'package:robot_ucab_app/features/auth/escaneo_pista.dart';

void main() {
  group('EscaneoPista (Gemelo Digital · modo básico)', () {
    test('recorre las 3 etapas en orden y produce métricas completas', () {
      final EscaneoPista s = EscaneoPista(pistaId: 'P1', largoEstimadoM: 9.0);
      expect(s.etapa, EtapaEscaneo.lecturaLenta);
      expect(s.metricas, isNull);
      final List<EtapaEscaneo> vistas = <EtapaEscaneo>[s.etapa];
      for (int i = 0; i < 10000 && !s.completado; i++) {
        s.avanzar(0.1);
        if (vistas.last != s.etapa) vistas.add(s.etapa);
      }
      expect(vistas, <EtapaEscaneo>[
        EtapaEscaneo.lecturaLenta,
        EtapaEscaneo.pasadaNormal,
        EtapaEscaneo.viaje1,
        EtapaEscaneo.viaje2,
        EtapaEscaneo.viaje3,
        EtapaEscaneo.completado,
      ]);
      final MetricasPista m = s.metricas!;
      expect(m.completa, isTrue);
      expect(m.largoM, closeTo(9.0, 0.01));
      expect(m.puntosControlM, <double>[3.0, 6.0, 9.0]);
      expect(m.segmentosValidados, <bool>[true, true, true]);
      expect(m.firmaParedesCm.length, 3);
      expect(s.tiemposViajeS.length, 3);
      s.dispose();
    });

    test('Etapa 1 fija el largo y el perfil de radar; Etapa 2 los PC1–PC3', () {
      final EscaneoPista s = EscaneoPista(pistaId: 'P1', largoEstimadoM: 6.0);
      expect(s.largoMedidoM, isNull);
      expect(s.puntosControlM, isEmpty);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.pasadaNormal);
      expect(s.largoMedidoM, closeTo(6.0, 0.01));
      expect(s.cuentasOdometria, greaterThan(0));
      expect(s.frenteMedioCm, isNotNull);
      expect(s.puntosControlM, isEmpty);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.viaje1);
      expect(s.puntosControlM, <double>[2.0, 4.0, 6.0]);
      expect(s.tramoActual, (0.0, 2.0));
      expect(s.segmentosValidados, <bool>[false, false, false]);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.viaje2);
      expect(s.tramoActual, (2.0, 4.0));
      expect(s.segmentosValidados, <bool>[true, false, false]);
      s.dispose();
    });

    test('completarEscaneo pasa la pista a configurada y la deja activa', () {
      final CatalogoPistas c = CatalogoPistas();
      final PistaLocal nueva = c.agregarPista(
        nombre: 'Pasillo',
        longitudM: 7.4,
      )!;
      c.seleccionar('A');
      final EscaneoPista s = EscaneoPista(
        pistaId: nueva.id,
        largoEstimadoM: nueva.longitudM,
      );
      // Métricas incompletas no configuran la pista
      expect(
        c.completarEscaneo(
          nueva.id,
          const MetricasPista(
            largoM: 7.4,
            puntosControlM: <double>[],
            segmentosValidados: <bool>[],
          ),
        ),
        isFalse,
      );
      expect(c.porId(nueva.id)!.configurada, isFalse);
      s.completarTodo();
      expect(c.completarEscaneo(nueva.id, s.metricas!), isTrue);
      final PistaLocal p = c.porId(nueva.id)!;
      expect(p.estado, EstadoPista.configurada);
      expect(p.torresControl, 0);
      expect(p.metricas!.segmentosValidados, <bool>[true, true, true]);
      expect(c.activaId, nueva.id);
      expect(c.activaConfigurada, isTrue);
      expect(c.completarEscaneo('ZZ', s.metricas!), isFalse);
      s.dispose();
      c.dispose();
    });
  });
}
