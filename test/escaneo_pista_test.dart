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
      expect(m.puntosControlM, <double>[3.0, 6.0, 9.0]); // tercios equitativos (P05)
      expect(m.segmentosValidados, <bool>[true, true, true]);
      expect(m.lecturasPorSegmento, <int>[3, 3, 3]);
      expect(s.totalLecturasCompletadas, 9);
      expect(m.firmaParedesCm.length, 3);
      expect(s.tiemposViajeS.length, 3);
      s.dispose();
    });

    test('Etapa 1 fija el largo y el perfil de radar; Etapa 2 los PC1–PC3 equitativos (L/3)', () {
      final EscaneoPista s = EscaneoPista(pistaId: 'P1', largoEstimadoM: 6.0);
      expect(s.largoMedidoM, isNull);
      expect(s.puntosControlM, isEmpty);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.pasadaNormal);
      expect(s.largoMedidoM, closeTo(6.0, 0.01));
      expect(s.distanciaVerificada, isTrue);
      expect(s.cuentasOdometria, greaterThan(0));
      expect(s.frenteMedioCm, isNotNull);
      expect(s.puntosControlM, isEmpty);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.viaje1);
      expect(s.puntosControlM, <double>[2.0, 4.0, 6.0]); // L/3, 2·L/3, L
      expect(s.tramoActual, (0.0, 2.0));
      expect(s.segmentosValidados, <bool>[false, false, false]);
      expect(s.lecturasSegmento, <int>[0, 0, 0]);
      s.avanzar(s.duracionEtapaS + 0.01);
      expect(s.etapa, EtapaEscaneo.viaje2);
      expect(s.tramoActual, (2.0, 4.0));
      expect(s.segmentosValidados, <bool>[true, false, false]);
      expect(s.lecturasSegmento, <int>[3, 0, 0]);
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

    test(
      'descubrimiento progresivo (sin silueta previa en Fase 1, trazo en Fase 2 y perfil por sección en Fase 3)',
      () {
        final EscaneoPista s = EscaneoPista(pistaId: 'P2', largoEstimadoM: 9.0);
        expect(s.siluetaPreviaVisible, isFalse);
        expect(s.etapa, EtapaEscaneo.lecturaLenta);
        expect(s.fraccionRutaDescubierta, 0.0);
        s.avanzar(s.duracionEtapaS * 0.5);
        expect(s.fraccionRutaDescubierta, 0.0);
        expect(s.puntosControlM, isEmpty);

        // Fase 2: primer dibujo progresivo
        s.avanzar(s.duracionEtapaS * 0.5 + 0.01);
        expect(s.etapa, EtapaEscaneo.pasadaNormal);
        s.avanzar(s.duracionEtapaS * 0.5);
        expect(s.fraccionRutaDescubierta, closeTo(0.5, 0.05));

        // Al terminar Fase 3: 3 perfiles de sección consolidados
        s.completarTodo();
        expect(s.fraccionRutaDescubierta, 1.0);
        final MetricasPista m = s.metricas!;
        expect(m.perfilesSeccion.length, 3);
        for (int i = 0; i < 3; i++) {
          expect(m.perfilesSeccion[i].muestrasViajes, 3);
          expect(m.perfilesSeccion[i].paredFijaCm, greaterThan(100));
          expect(m.perfilesSeccion[i].tiempoEstimadoS, greaterThan(0));
        }
        s.dispose();
      },
    );

    test(
      'diferencia pared fija calibrada vs obstáculo nuevo y afina incrementalmente en operación normal',
      () {
        final CatalogoPistas c = CatalogoPistas();
        final PistaLocal p = c.agregarPista(
          nombre: 'Pista B',
          longitudM: 9.0,
          geometria: TipoGeometriaPista.lineal,
        )!;
        final EscaneoPista s = EscaneoPista(
          pistaId: p.id,
          largoEstimadoM: 9.0,
          geometria: p.geometria,
        );
        s.completarTodo();
        c.completarEscaneo(p.id, s.metricas!);

        final MetricasPista base = c.porId(p.id)!.metricas!;
        final double paredS1 = base.perfilesSeccion[0].paredFijaCm;

        // Lectura dentro del margen de la pared calibrada -> pared fija
        expect(
          base.clasificarLecturaRadar(posicionM: 1.5, frenteCm: paredS1 - 5),
          ClasificacionRadar.paredFija,
        );
        // Lectura muy por debajo de la pared fija -> obstáculo temporal nuevo
        expect(
          base.clasificarLecturaRadar(posicionM: 1.5, frenteCm: 35.0),
          ClasificacionRadar.obstaculoNuevo,
        );

        // Aprendizaje continuo: un viaje normal afina tiempos y no deja que un
        // obstáculo temporal corrompa el perfil de pared fija
        expect(
          c.registrarViajeOperacion(
            p.id,
            duracionTotalS: 21.0,
            velocidadMediaMs: 0.43,
            lecturasParedCm: <double>[30.0, paredS1, paredS1],
          ),
          isTrue,
        );
        final MetricasPista afinada = c.porId(p.id)!.metricas!;
        expect(afinada.viajesOperacion, 1);
        expect(afinada.perfilesSeccion[0].muestrasViajes, 4);
        // La lectura anómala de 30 cm NO corrompió paredFijaCm de la sección 1
        expect(afinada.perfilesSeccion[0].paredFijaCm, paredS1);
        s.dispose();
        c.dispose();
      },
    );
  });
}
