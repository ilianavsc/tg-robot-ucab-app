import 'package:flutter/foundation.dart';

import '../../core/pistas/trazado_pista.dart';
import 'sesion_local.dart';

export '../../core/pistas/trazado_pista.dart'
    show largoCanonicoM, largoPistaAM, puntosControlPara;

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
    this.frenteMinimoCm,
    this.frenteMedioCm,
    this.firmaParedesCm = const <double>[],
    this.giroTotalGrados = 360,
    this.lineaVistaPct = 100,
  });

  /// Largo medido con la odometría (m).
  final double largoM;

  /// Posición de PC1, PC2 y PC3 (m desde el inicio). PC3 cierra la vuelta.
  final List<double> puntosControlM;

  /// Segmento 1, 2 y 3 validados en los 3 viajes de verificación.
  final List<bool> segmentosValidados;

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
}

/// Configuración de una pista disponible en el laboratorio.
class PistaLocal {
  const PistaLocal({
    required this.id,
    required this.nombre,
    required this.longitudM,
    this.torresControl = 0,
    this.base = false,
    this.estado = EstadoPista.pendiente,
    this.metricas,
  });

  final String id;
  final String nombre;

  /// Longitud en metros: la estimada al crearla y, tras el escaneo, la medida.
  final double longitudM;

  /// Torres de control BLE. Por ahora toda pista es **básica**: `0`.
  final int torresControl;

  /// `true` para las pistas precargadas del proyecto.
  final bool base;

  final EstadoPista estado;

  /// Métricas del escaneo (solo en pistas configuradas).
  final MetricasPista? metricas;

  bool get configurada => estado == EstadoPista.configurada;

  PistaLocal copiarCon({
    double? longitudM,
    EstadoPista? estado,
    MetricasPista? metricas,
  }) => PistaLocal(
    id: id,
    nombre: nombre,
    longitudM: longitudM ?? this.longitudM,
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
    _pistas.add(
      PistaLocal(
        id: 'A',
        nombre: 'Pista A · Circuito histórico',
        longitudM: 8.05,
        base: true,
        estado: EstadoPista.configurada,
        metricas: MetricasPista(
          largoM: 8.05,
          puntosControlM: puntosControlPara(8.05),
          segmentosValidados: const <bool>[true, true, true],
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
  }) {
    final String limpio = nombre.trim();
    if (limpio.isEmpty || longitudM < 1.0 || longitudM > 50.0) return null;
    final PistaLocal nueva = PistaLocal(
      id: 'P${_contador++}',
      nombre: limpio,
      longitudM: double.parse(longitudM.toStringAsFixed(2)),
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
