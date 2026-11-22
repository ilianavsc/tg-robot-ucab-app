import 'package:flutter/foundation.dart';

import '../../core/pistas/trazado_pista.dart';
import 'sesion_local.dart';

export '../../core/pistas/trazado_pista.dart'
    show
        TipoGeometriaPista,
        largoCanonicoM,
        largoPistaAM,
        puntosControlEquitativos,
        puntosControlPara;

/// Estado de una pista en el catálogo.
///
/// * [configurada]: ya pasó por el escaneo completo del Gemelo Digital
///   (lectura lenta, pasada normal y 3 viajes de verificación).
/// * [pendiente]: recién creada desde `+ Nueva pista`; está **en escaneo** y
///   el Operador no puede iniciar sesión con ella hasta completarlo.
enum EstadoPista {
  configurada('configurada', 'Configurada'),
  pendiente('en_escaneo', 'Pendiente · en escaneo');

  const EstadoPista(this.clave, this.etiqueta);

  /// Clave corta (`configurada` / `en_escaneo`).
  final String clave;

  /// Texto para la interfaz.
  final String etiqueta;
}

/// Tipo de viaje soportado por la pista según sus torres de control BLE.
///
/// * [circuitoCerrado] (`torresControl == 0`): solo recorrido completo en
///   circuito cerrado, sin entregas ni destinos de laboratorio.
/// * [entregaLaboratorio] (`torresControl >= 1`): reservado para la siguiente
///   fase con torre de control y retorno.
enum TipoViajePista {
  circuitoCerrado('circuito_cerrado', 'Circuito cerrado'),
  entregaLaboratorio('entrega_laboratorio', 'Entrega a laboratorio');

  const TipoViajePista(this.clave, this.etiqueta);

  final String clave;
  final String etiqueta;
}

/// Clasificación de una lectura ultrasónica frontal frente al perfil de paredes
/// fijas calibrado durante el escaneo del Gemelo Digital.
enum ClasificacionRadar {
  libre('Libre'),
  paredFija('Pared fija calibrada'),
  obstaculoNuevo('Obstáculo nuevo');

  const ClasificacionRadar(this.etiqueta);

  final String etiqueta;
}

/// Perfil de referencia calibrado para una sección de la pista (`Inicio → PC1`,
/// `PC1 → PC2` o `PC2 → PC3`). Se consolida en los 3 escaneos de la Fase 3 y se
/// afina de forma incremental con cada viaje normal posterior.
class PerfilSeccion {
  const PerfilSeccion({
    required this.indice,
    required this.nombre,
    required this.desdeM,
    required this.hastaM,
    required this.tiempoEstimadoS,
    required this.velocidadRefMs,
    required this.paredFijaCm,
    this.margenObstaculoCm = 25.0,
    this.muestrasViajes = 3,
  });

  final int indice;
  final String nombre;
  final double desdeM;
  final double hastaM;
  final double tiempoEstimadoS;
  final double velocidadRefMs;

  /// Distancia ultrasónica frontal esperada a paredes/estructuras fijas (cm).
  final double paredFijaCm;

  /// Umbral de desviación (cm) por debajo de [paredFijaCm] para distinguir un
  /// obstáculo temporal nuevo de una pared fija calibrada.
  final double margenObstaculoCm;

  /// Cantidad de lecturas/viajes acumulados en el perfil incremental.
  final int muestrasViajes;

  /// `true` si [lecturaCm] está significativamente más cerca que la pared fija
  /// aprendida durante la calibración sin obstáculos.
  bool esObstaculoAnomalo(double lecturaCm) {
    if (lecturaCm <= 0) return false;
    return lecturaCm < (paredFijaCm - margenObstaculoCm);
  }

  /// `true` si [lecturaCm] coincide con la pared fija aprendida en esta sección.
  bool coincideConParedFija(double lecturaCm) {
    if (lecturaCm <= 0) return false;
    return (lecturaCm - paredFijaCm).abs() <= margenObstaculoCm;
  }

  /// Afina incrementalmente las métricas de esta sección con un viaje normal.
  PerfilSeccion afinarConViaje({
    required double tiempoS,
    required double velocidadMs,
    double? lecturaParedCm,
  }) {
    final int n = muestrasViajes + 1;
    double avg(double prev, double nuevo) =>
        double.parse(((prev * muestrasViajes + nuevo) / n).toStringAsFixed(2));
    // Solo incorpora la lectura de radar al perfil de pared fija si no es un
    // obstáculo anómalo temporal.
    final bool paredValida =
        lecturaParedCm != null &&
        lecturaParedCm > 0 &&
        !esObstaculoAnomalo(lecturaParedCm);
    return PerfilSeccion(
      indice: indice,
      nombre: nombre,
      desdeM: desdeM,
      hastaM: hastaM,
      tiempoEstimadoS: avg(tiempoEstimadoS, tiempoS),
      velocidadRefMs: avg(velocidadRefMs, velocidadMs),
      paredFijaCm: paredValida
          ? avg(paredFijaCm, lecturaParedCm)
          : paredFijaCm,
      margenObstaculoCm: margenObstaculoCm,
      muestrasViajes: n,
    );
  }
}

/// Métricas base que deja el escaneo del Gemelo Digital (modo básico).
///
/// Todo es **simulación (SIL)**: el largo sale de la odometría simulada, el
/// perfil de radar y la firma de paredes del HC-SR04P frontal son de la
/// vuelta simulada **[PENDIENTE DE MEDICIÓN FÍSICA]**.
class MetricasPista {
  const MetricasPista({
    required this.largoM,
    required this.puntosControlM,
    required this.segmentosValidados,
    this.lecturasPorSegmento = const <int>[3, 3, 3],
    this.perfilesSeccion = const <PerfilSeccion>[],
    this.viajesOperacion = 0,
    this.frenteMinimoCm,
    this.frenteMedioCm,
    this.firmaParedesCm = const <double>[],
    this.giroTotalGrados = 360,
    this.lineaVistaPct = 100,
  });

  /// Largo medido con la odometría (m).
  final double largoM;

  /// Posición de PC1, PC2 y PC3 (m desde el inicio). En pistas escaneadas con
  /// la lógica de P05 se distribuyen en tercios equitativos (`L/3`, `2·L/3`, `L`).
  final List<double> puntosControlM;

  /// Segmento 1, 2 y 3 validados tras 3 lecturas por segmento.
  final List<bool> segmentosValidados;

  /// Cantidad de lecturas completadas por cada uno de los 3 segmentos (meta: 3).
  final List<int> lecturasPorSegmento;

  /// Perfiles de referencia consolidados por sección (Fase 3 + aprendizaje continuo).
  final List<PerfilSeccion> perfilesSeccion;

  /// Cantidad de viajes en operación normal que ya afinaron el perfil de la pista.
  final int viajesOperacion;

  /// Perfil inicial del radar frontal (cm) en la lectura lenta.
  final double? frenteMinimoCm;
  final double? frenteMedioCm;

  /// Firma de paredes del radar delantero por segmento (cm), de la pasada normal.
  final List<double> firmaParedesCm;

  /// Giro total medido por la MPU-6050 en la vuelta (circuito cerrado ≈ 360°).
  final double giroTotalGrados;

  /// Porcentaje de la vuelta con la cinta vista por los 4 TCRT5000.
  final double lineaVistaPct;

  bool get completa =>
      puntosControlM.length == 3 &&
      segmentosValidados.length == 3 &&
      segmentosValidados.every((bool v) => v);

  /// Devuelve el [PerfilSeccion] correspondiente a [posicionM] sobre la pista.
  PerfilSeccion? seccionEn(double posicionM) {
    if (perfilesSeccion.isEmpty) return null;
    final double pos = posicionM.clamp(0.0, largoM);
    for (final PerfilSeccion s in perfilesSeccion) {
      if (pos <= s.hastaM + 1e-6) return s;
    }
    return perfilesSeccion.last;
  }

  /// Distingue si [frenteCm] en [posicionM] corresponde a una pared fija
  /// aprendida en la calibración, a un obstáculo temporal nuevo o a vía libre.
  ClasificacionRadar clasificarLecturaRadar({
    required double posicionM,
    required double? frenteCm,
  }) {
    if (frenteCm == null || frenteCm <= 0) return ClasificacionRadar.libre;
    final PerfilSeccion? sec = seccionEn(posicionM);
    if (sec == null) {
      return frenteCm < 50.0
          ? ClasificacionRadar.obstaculoNuevo
          : ClasificacionRadar.libre;
    }
    if (sec.esObstaculoAnomalo(frenteCm)) {
      return ClasificacionRadar.obstaculoNuevo;
    }
    if (sec.coincideConParedFija(frenteCm)) {
      return ClasificacionRadar.paredFija;
    }
    return ClasificacionRadar.libre;
  }

  /// Devuelve nuevas métricas afinadas con un viaje completado en operación.
  MetricasPista afinarConViaje({
    required double duracionTotalS,
    required double velocidadMediaMs,
    List<double>? lecturasParedCm,
  }) {
    if (perfilesSeccion.isEmpty) return this;
    final double durSeccion = duracionTotalS / perfilesSeccion.length;
    final List<PerfilSeccion> afinados = <PerfilSeccion>[
      for (int i = 0; i < perfilesSeccion.length; i++)
        perfilesSeccion[i].afinarConViaje(
          tiempoS: durSeccion,
          velocidadMs: velocidadMediaMs,
          lecturaParedCm:
              (lecturasParedCm != null && i < lecturasParedCm.length)
              ? lecturasParedCm[i]
              : null,
        ),
    ];
    return MetricasPista(
      largoM: largoM,
      puntosControlM: puntosControlM,
      segmentosValidados: segmentosValidados,
      lecturasPorSegmento: lecturasPorSegmento,
      perfilesSeccion: afinados,
      viajesOperacion: viajesOperacion + 1,
      frenteMinimoCm: frenteMinimoCm,
      frenteMedioCm: frenteMedioCm,
      firmaParedesCm: <double>[
        for (final PerfilSeccion s in afinados) s.paredFijaCm,
      ],
      giroTotalGrados: giroTotalGrados,
      lineaVistaPct: lineaVistaPct,
    );
  }
}

/// Configuración de una pista disponible en el laboratorio.
class PistaLocal {
  const PistaLocal({
    required this.id,
    required this.nombre,
    required this.longitudM,
    this.geometria = TipoGeometriaPista.circuitoCerrado,
    this.torresControl = 0,
    this.base = false,
    this.estado = EstadoPista.pendiente,
    this.metricas,
  });

  final String id;
  final String nombre;

  /// Longitud en metros: la estimada al crearla y, tras el escaneo, la medida.
  final double longitudM;

  /// Geometría elegida al crear la pista: **Circuito cerrado** o **Lineal**.
  final TipoGeometriaPista geometria;

  /// Torres de control BLE. Por ahora toda pista es **básica**: `0`.
  final int torresControl;

  /// `true` para las pistas precargadas del proyecto.
  final bool base;

  final EstadoPista estado;

  /// Métricas del escaneo (solo en pistas configuradas).
  final MetricasPista? metricas;

  bool get configurada => estado == EstadoPista.configurada;
  bool get esLineal => geometria == TipoGeometriaPista.lineal;

  /// Tipo de viaje según `torresControl`: `0` = circuito cerrado (sin
  /// entregas), `>= 1` = entrega a laboratorio.
  TipoViajePista get tipoViaje => torresControl == 0
      ? TipoViajePista.circuitoCerrado
      : TipoViajePista.entregaLaboratorio;

  bool get esCircuitoCerrado => tipoViaje == TipoViajePista.circuitoCerrado;

  PistaLocal copiarCon({
    double? longitudM,
    TipoGeometriaPista? geometria,
    EstadoPista? estado,
    MetricasPista? metricas,
  }) => PistaLocal(
    id: id,
    nombre: nombre,
    longitudM: longitudM ?? this.longitudM,
    geometria: geometria ?? this.geometria,
    torresControl: torresControl,
    base: base,
    estado: estado ?? this.estado,
    metricas: metricas ?? this.metricas,
  );
}

/// Catálogo local en memoria de pistas seleccionables desde el Login.
///
/// Arranca con `Pista A (8,05 m)` **configurada** (simula una pista que ya pasó
/// por el escaneo completo y la verificación de sus 3 segmentos) y sin pista
/// seleccionada (`activa == null`). Las pistas nuevas nacen en modo básico
/// (`torresControl = 0`) y **pendientes** hasta completar su escaneo.
class CatalogoPistas extends ChangeNotifier {
  CatalogoPistas() {
    final List<double> pcsA = puntosControlPara(8.05);
    _pistas.add(
      PistaLocal(
        id: 'A',
        nombre: 'Pista A · Circuito histórico',
        longitudM: 8.05,
        base: true,
        estado: EstadoPista.configurada,
        metricas: MetricasPista(
          largoM: 8.05,
          puntosControlM: pcsA,
          segmentosValidados: const <bool>[true, true, true],
          perfilesSeccion: <PerfilSeccion>[
            PerfilSeccion(
              indice: 0,
              nombre: 'Sección 1 (Inicio → PC1)',
              desdeM: 0,
              hastaM: pcsA[0],
              tiempoEstimadoS: 6.5,
              velocidadRefMs: 0.41,
              paredFijaCm: 142.0,
            ),
            PerfilSeccion(
              indice: 1,
              nombre: 'Sección 2 (PC1 → PC2)',
              desdeM: pcsA[0],
              hastaM: pcsA[1],
              tiempoEstimadoS: 3.3,
              velocidadRefMs: 0.41,
              paredFijaCm: 136.0,
            ),
            PerfilSeccion(
              indice: 2,
              nombre: 'Sección 3 (PC2 → cierre)',
              desdeM: pcsA[1],
              hastaM: 8.05,
              tiempoEstimadoS: 9.8,
              velocidadRefMs: 0.41,
              paredFijaCm: 145.0,
            ),
          ],
          firmaParedesCm: const <double>[142.0, 136.0, 145.0],
        ),
      ),
    );
  }

  final List<PistaLocal> _pistas = <PistaLocal>[];
  String? _activaId;
  int _contador = 1;

  List<PistaLocal> get pistas => List<PistaLocal>.unmodifiable(_pistas);
  String? get activaId => _activaId;
  bool get tienePistaActiva => _activaId != null;

  /// `true` si hay una pista activa y ya está configurada (requisito del Operador).
  bool get activaConfigurada => activa?.configurada ?? false;

  /// Regla de acceso centralizada: el Operador entra solo con una pista
  /// **configurada**; el Administrador con cualquier pista activa.
  bool puedeIniciarSesion(RolUsuario rol) =>
      rol == RolUsuario.administrador ? tienePistaActiva : activaConfigurada;

  PistaLocal? get activa => _activaId == null ? null : porId(_activaId!);

  PistaLocal? porId(String id) {
    for (final PistaLocal p in _pistas) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool seleccionar(String id) {
    final bool existe = _pistas.any((PistaLocal p) => p.id == id);
    if (!existe || _activaId == id) return existe;
    _activaId = id;
    notifyListeners();
    return true;
  }

  /// Registra una pista nueva en **modo básico** (`torresControl = 0`) con su
  /// nombre y una longitud estimada (`1,0–50,0 m`). Nace **pendiente** (en
  /// escaneo) y queda seleccionada; el escaneo la pasa a configurada.
  PistaLocal? agregarPista({
    required String nombre,
    required double longitudM,
    TipoGeometriaPista geometria = TipoGeometriaPista.circuitoCerrado,
    int torresControl = 0,
  }) {
    final String limpio = nombre.trim();
    if (limpio.isEmpty || longitudM < 1.0 || longitudM > 50.0) return null;
    final PistaLocal nueva = PistaLocal(
      id: 'P${_contador++}',
      nombre: limpio,
      longitudM: double.parse(longitudM.toStringAsFixed(2)),
      geometria: geometria,
      torresControl: torresControl < 0 ? 0 : torresControl,
    );
    _pistas.add(nueva);
    _activaId = nueva.id;
    notifyListeners();
    return nueva;
  }

  /// Cierra el escaneo: guarda las métricas, pasa la pista a **configurada**
  /// y la deja seleccionada como activa. Devuelve `false` si la pista no
  /// existe o las métricas no traen los 3 segmentos validados.
  bool completarEscaneo(String id, MetricasPista metricas) {
    final int i = _pistas.indexWhere((PistaLocal p) => p.id == id);
    if (i < 0 || !metricas.completa) return false;
    _pistas[i] = _pistas[i].copiarCon(
      longitudM: metricas.largoM,
      estado: EstadoPista.configurada,
      metricas: metricas,
    );
    _activaId = id;
    notifyListeners();
    return true;
  }

  /// Afina incrementalmente las métricas de una pista ya configurada tras
  /// completar un viaje en operación normal (aprendizaje continuo).
  bool registrarViajeOperacion(
    String id, {
    required double duracionTotalS,
    required double velocidadMediaMs,
    List<double>? lecturasParedCm,
  }) {
    final int i = _pistas.indexWhere((PistaLocal p) => p.id == id);
    if (i < 0) return false;
    final PistaLocal pista = _pistas[i];
    if (!pista.configurada || pista.metricas == null) return false;
    _pistas[i] = pista.copiarCon(
      metricas: pista.metricas!.afinarConViaje(
        duracionTotalS: duracionTotalS,
        velocidadMediaMs: velocidadMediaMs,
        lecturasParedCm: lecturasParedCm,
      ),
    );
    notifyListeners();
    return true;
  }

  /// Elimina una pista del catálogo. Si era la pista activa, limpia la
  /// selección (`activa == null`) para volver a exigir pista en el Login.
  bool eliminarPista(String id) {
    final int i = _pistas.indexWhere((PistaLocal p) => p.id == id);
    if (i < 0) return false;
    _pistas.removeAt(i);
    if (_activaId == id) _activaId = null;
    notifyListeners();
    return true;
  }
}
