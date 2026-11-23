import 'dart:math' as math;

import '../contracts/generated/robot_contract.dart';

/// Tipo de ruta operacional de la Capa 3.
enum TipoRutaOperacional {
  cerrada('cerrada', 'Ruta Cerrada'),
  lineal('lineal', 'Ruta Lineal');

  const TipoRutaOperacional(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static TipoRutaOperacional desdeClave(String? clave) =>
      clave == 'lineal' ? TipoRutaOperacional.lineal : TipoRutaOperacional.cerrada;
}

/// 10 estados de la Máquina de Rutas (Capa 3A), alineados 1:1 con
/// `RobotMqttContract.estadosRuta` (`9e01afd`).
enum EstadoRutaOperacional {
  sinRuta('SIN_RUTA'),
  escaneoIda('ESCANEO_IDA'),
  esperaReposicion('ESPERA_REPOSICION'),
  escaneoRetorno('ESCANEO_RETORNO'),
  operacionBucle('OPERACION_BUCLE'),
  reescaneoParada('REESCANEO_PARADA'),
  operacionConParada('OPERACION_CON_PARADA'),
  pausaObstaculo('PAUSA_OBSTACULO'),
  errorSeguridad('ERROR_SEGURIDAD'),
  recuperacionManual('RECUPERACION_MANUAL');

  const EstadoRutaOperacional(this.clave);
  final String clave;

  static EstadoRutaOperacional? desdeClave(String? clave) {
    for (final EstadoRutaOperacional e in values) {
      if (e.clave == clave) return e;
    }
    return null;
  }
}

/// 5 estados de la Máquina de Pedidos (Capa 3B · ortogonal), alineados 1:1 con
/// `RobotMqttContract.estadosPedido` (`9e01afd`).
enum EstadoPedidoOperacional {
  sinPedido('SIN_PEDIDO'),
  solicitado('SOLICITADO'),
  enTransito('EN_TRANSITO'),
  cancelacionSegura('CANCELACION_SEGURA'),
  entregado('ENTREGADO');

  const EstadoPedidoOperacional(this.clave);
  final String clave;

  static EstadoPedidoOperacional? desdeClave(String? clave) {
    for (final EstadoPedidoOperacional e in values) {
      if (e.clave == clave) return e;
    }
    return null;
  }
}

/// 3 alertas críticas del MPU-6050 con prioridad absoluta sobre movimiento.
enum AlertaMpu6050 {
  impacto('impacto', 'Impacto detectado'),
  inclinacion('inclinacion', 'Inclinación / vuelco'),
  atascamiento('atascamiento', 'Atascamiento de tracción');

  const AlertaMpu6050(this.clave, this.etiqueta);
  final String clave;
  final String etiqueta;

  static AlertaMpu6050? desdeClave(String? clave) {
    for (final AlertaMpu6050 a in values) {
      if (a.clave == clave) return a;
    }
    return null;
  }
}

/// Telemetría continua QoS 0 del tópico `sensores/inercial` (MPU-6050).
class LecturaInercial {
  const LecturaInercial({
    required this.pitch,
    required this.roll,
    required this.acelG,
    required this.timestampMs,
    this.alerta,
  });

  final double pitch;
  final double roll;
  final double acelG;
  final AlertaMpu6050? alerta;
  final int timestampMs;

  factory LecturaInercial.fromJson(Map<String, dynamic> json) {
    return LecturaInercial(
      pitch: _num(json['pitch']),
      roll: _num(json['roll']),
      acelG: _num(json['acel_g']),
      alerta: AlertaMpu6050.desdeClave(json['alerta']?.toString()),
      timestampMs: _entero(json['timestamp']),
    );
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : 0.0;
  static int _entero(dynamic v) => v is num ? v.round() : 0;
}

/// Referencia inmutable de una ruta aprendida (conservada en `CANCELACION_SEGURA`).
class RutaAprendidaOperacional {
  const RutaAprendidaOperacional({
    required this.tipoRuta,
    required this.largoM,
    required this.paradaConfigurada,
    required this.paradaNombre,
    required this.dobleEscaneo,
  });

  final TipoRutaOperacional tipoRuta;
  final double largoM;
  final bool paradaConfigurada;
  final String paradaNombre;
  final bool dobleEscaneo;
}

/// Pedido operacional activo en la Capa 3B.
class PedidoOperacional {
  const PedidoOperacional({
    required this.requestId,
    required this.paradaId,
    required this.conCarga,
    this.componente = 'Kit de laboratorio',
  });

  final String requestId;
  final String paradaId;
  final bool conCarga;
  final String componente;
}

/// Resultado compacto de una transición de Capa 3.
class ResultadoCapa3 {
  const ResultadoCapa3({required this.ok, this.motivo});

  final bool ok;
  final String? motivo;
}

/// Controlador puro (sin dependencias de UI) de la **Capa 3 Operacional**:
/// Máquina de Rutas (10 estados) + Máquina de Pedidos (5 estados) + MPU-6050 +
/// tiempos reales de escaneo (`0,41 m/s` / `0,16 m/s`) y reloj `1x / 2x / 4x`.
class Capa3OperacionalController {
  Capa3OperacionalController({
    TipoRutaOperacional tipoRuta = TipoRutaOperacional.cerrada,
    double largoM = RobotTrackContract.longitudCanonicaM,
    bool paradaConfigurada = false,
    String paradaNombre = '',
  }) : _tipoRuta = tipoRuta,
       _largoM = largoM > 0 ? largoM : RobotTrackContract.longitudCanonicaM,
       _paradaNombre = paradaNombre.trim(),
       _paradaConfigurada = paradaConfigurada && paradaNombre.trim().isNotEmpty;

  static const double velLentaMs = 0.16;
  static const double velNormalMs = 0.41;
  static const int usosParaParada = 3;
  static const List<int> escalasReloj = <int>[1, 2, 4];

  TipoRutaOperacional _tipoRuta;
  double _largoM;
  bool _paradaConfigurada;
  String _paradaNombre;
  EstadoRutaOperacional _estadoRuta = EstadoRutaOperacional.sinRuta;
  EstadoRutaOperacional? _estadoPrevioPausa;
  EstadoPedidoOperacional _estadoPedido = EstadoPedidoOperacional.sinPedido;
  int _usosCompletados = 0;
  RutaAprendidaOperacional? _rutaAprendida;
  PedidoOperacional? _pedidoActivo;
  AlertaMpu6050? _alertaMpu;
  LecturaInercial? _ultimaLecturaInercial;
  int _escalaReloj = 1;
  double _velEscaneoMs = velNormalMs;
  double _tiempoSimS = 0;
  double _tiempoRealS = 0;
  double _progresoPasadaM = 0;
  int _ultimoTimestampRutasMs = 0;
  int _ultimoTimestampPedidosMs = 0;
  int _contadorPedidos = 0;

  // --------------------------------------------------------------- lecturas
  TipoRutaOperacional get tipoRuta => _tipoRuta;
  double get largoM => _largoM;
  bool get paradaConfigurada => _paradaConfigurada;
  String get paradaNombre => _paradaNombre;
  EstadoRutaOperacional get estadoRuta => _estadoRuta;
  EstadoPedidoOperacional get estadoPedido => _estadoPedido;
  int get usosCompletados => _usosCompletados;
  RutaAprendidaOperacional? get rutaAprendida => _rutaAprendida;
  PedidoOperacional? get pedidoActivo => _pedidoActivo;
  AlertaMpu6050? get alertaMpu => _alertaMpu;
  LecturaInercial? get ultimaLecturaInercial => _ultimaLecturaInercial;
  int get escalaReloj => _escalaReloj;
  double get velEscaneoMs => _velEscaneoMs;
  double get tiempoSimS => _tiempoSimS;
  double get tiempoRealS => _tiempoRealS;
  double get progresoPasadaM => _progresoPasadaM;

  /// Invariante de seguridad: bloquea órdenes de movimiento en
  /// `ESPERA_REPOSICION`, `ERROR_SEGURIDAD` y `RECUPERACION_MANUAL`.
  bool get puedeMover =>
      !RobotMqttContract.movimientoBloqueadoEnEstados.contains(
        _estadoRuta.clave,
      );

  bool get movimientoBloqueado => !puedeMover;

  bool get puedeReescanearParada =>
      _tipoRuta == TipoRutaOperacional.cerrada &&
      !_paradaConfigurada &&
      _estadoRuta == EstadoRutaOperacional.operacionBucle &&
      _usosCompletados >= usosParaParada;

  bool get puedeSolicitarPedido =>
      _estadoRuta == EstadoRutaOperacional.operacionConParada &&
      _paradaConfigurada &&
      _estadoPedido == EstadoPedidoOperacional.sinPedido;

  double get duracionPasadaS => _r2(_largoM / _velEscaneoMs);

  double get duracionEstimadaEscaneoS => _tipoRuta == TipoRutaOperacional.lineal
      ? _r2(duracionPasadaS * 2)
      : duracionPasadaS;

  double get tiempoRestanteEstimadoS {
    switch (_estadoRuta) {
      case EstadoRutaOperacional.sinRuta:
        return duracionEstimadaEscaneoS;
      case EstadoRutaOperacional.escaneoIda:
        final double restIda = math.max(0.0, _largoM - _progresoPasadaM) / _velEscaneoMs;
        return _tipoRuta == TipoRutaOperacional.lineal
            ? _r2(restIda + _largoM / _velEscaneoMs)
            : _r2(restIda);
      case EstadoRutaOperacional.esperaReposicion:
        return _r2(_largoM / _velEscaneoMs);
      case EstadoRutaOperacional.escaneoRetorno:
      case EstadoRutaOperacional.reescaneoParada:
        return _r2(math.max(0.0, _largoM - _progresoPasadaM) / _velEscaneoMs);
      default:
        return 0;
    }
  }

  // --------------------------------------------------------- configuración
  void setTipoRuta(TipoRutaOperacional nuevo) {
    _tipoRuta = nuevo;
    _estadoRuta = EstadoRutaOperacional.sinRuta;
    _estadoPrevioPausa = null;
    _estadoPedido = EstadoPedidoOperacional.sinPedido;
    _pedidoActivo = null;
    _usosCompletados = 0;
    _rutaAprendida = null;
    _alertaMpu = null;
    _tiempoSimS = 0;
    _tiempoRealS = 0;
    _progresoPasadaM = 0;
    if (nuevo == TipoRutaOperacional.cerrada) {
      _paradaConfigurada = _paradaNombre.isNotEmpty;
    }
  }

  void setLargoM(double largoM) {
    if (largoM > 0) _largoM = largoM;
  }

  bool configurarParada(String nombre) {
    _paradaNombre = nombre.trim();
    _paradaConfigurada = _paradaNombre.isNotEmpty;
    return _paradaConfigurada;
  }

  void setEscalaReloj(int factor) {
    _escalaReloj = escalasReloj.contains(factor) ? factor : 1;
  }

  void setVelocidadEscaneo({required bool lenta}) {
    _velEscaneoMs = lenta ? velLentaMs : velNormalMs;
  }

  // ------------------------------------------------------ Máquina de Rutas
  ResultadoCapa3 iniciarEscaneo() {
    if (!puedeMover) {
      return ResultadoCapa3(
        ok: false,
        motivo: 'movimiento_bloqueado_${_estadoRuta.clave.toLowerCase()}',
      );
    }
    if (_tipoRuta == TipoRutaOperacional.lineal && !_paradaConfigurada) {
      return const ResultadoCapa3(
        ok: false,
        motivo: 'parada_obligatoria_en_ruta_lineal',
      );
    }
    _estadoRuta = EstadoRutaOperacional.escaneoIda;
    _alertaMpu = null;
    _tiempoSimS = 0;
    _tiempoRealS = 0;
    _progresoPasadaM = 0;
    return const ResultadoCapa3(ok: true);
  }

  /// Avanza el reloj de simulación (`1x / 2x / 4x` solo escala tiempo sim).
  /// En `ESPERA_REPOSICION` jamás hay auto-retorno por timeout.
  void avanzarReloj(double dtRealS) {
    if (dtRealS <= 0) return;
    if (_estadoRuta == EstadoRutaOperacional.esperaReposicion) {
      _tiempoRealS = _r2(_tiempoRealS + dtRealS);
      return;
    }
    if (!puedeMover ||
        _estadoRuta == EstadoRutaOperacional.pausaObstaculo ||
        _estadoRuta == EstadoRutaOperacional.sinRuta) {
      return;
    }
    final double dtSim = dtRealS * _escalaReloj;
    _tiempoRealS = _r2(_tiempoRealS + dtRealS);
    _tiempoSimS = _r2(_tiempoSimS + dtSim);
    if (_estadoRuta == EstadoRutaOperacional.escaneoIda ||
        _estadoRuta == EstadoRutaOperacional.escaneoRetorno ||
        _estadoRuta == EstadoRutaOperacional.reescaneoParada) {
      _progresoPasadaM = math.min(
        _largoM,
        _r2(_progresoPasadaM + _velEscaneoMs * dtSim),
      );
    }
  }

  ResultadoCapa3 completarPasadaIda() {
    if (_estadoRuta != EstadoRutaOperacional.escaneoIda) {
      return const ResultadoCapa3(ok: false, motivo: 'estado_invalido');
    }
    _progresoPasadaM = _largoM;
    if (_tipoRuta == TipoRutaOperacional.lineal) {
      _estadoRuta = EstadoRutaOperacional.esperaReposicion;
      return const ResultadoCapa3(ok: true);
    }
    _rutaAprendida = RutaAprendidaOperacional(
      tipoRuta: TipoRutaOperacional.cerrada,
      largoM: _largoM,
      paradaConfigurada: _paradaConfigurada,
      paradaNombre: _paradaNombre,
      dobleEscaneo: false,
    );
    _estadoRuta = _paradaConfigurada
        ? EstadoRutaOperacional.operacionConParada
        : EstadoRutaOperacional.operacionBucle;
    return const ResultadoCapa3(ok: true);
  }

  ResultadoCapa3 confirmarReposicionamiento() {
    if (_estadoRuta != EstadoRutaOperacional.esperaReposicion) {
      return const ResultadoCapa3(ok: false, motivo: 'no_en_espera_reposicion');
    }
    _estadoRuta = EstadoRutaOperacional.escaneoRetorno;
    _progresoPasadaM = 0;
    return const ResultadoCapa3(ok: true);
  }

  ResultadoCapa3 completarPasadaRetorno() {
    if (_estadoRuta != EstadoRutaOperacional.escaneoRetorno) {
      return const ResultadoCapa3(ok: false, motivo: 'estado_invalido');
    }
    _progresoPasadaM = _largoM;
    _rutaAprendida = RutaAprendidaOperacional(
      tipoRuta: TipoRutaOperacional.lineal,
      largoM: _largoM,
      paradaConfigurada: true,
      paradaNombre: _paradaNombre,
      dobleEscaneo: true,
    );
    _estadoRuta = EstadoRutaOperacional.operacionConParada;
    return const ResultadoCapa3(ok: true);
  }

  /// Incrementa `usosCompletados` solo si el recorrido terminó sin fallo.
  int registrarUsoCompletado({required bool exitoso}) {
    if (_estadoRuta != EstadoRutaOperacional.operacionBucle &&
        _estadoRuta != EstadoRutaOperacional.operacionConParada) {
      return _usosCompletados;
    }
    if (exitoso) _usosCompletados++;
    return _usosCompletados;
  }

  ResultadoCapa3 iniciarReescaneoParada(String nombreParada) {
    if (!puedeReescanearParada) {
      return const ResultadoCapa3(ok: false, motivo: 'requiere_3_usos');
    }
    if (!configurarParada(nombreParada)) {
      return const ResultadoCapa3(ok: false, motivo: 'parada_requerida');
    }
    _estadoRuta = EstadoRutaOperacional.reescaneoParada;
    _progresoPasadaM = 0;
    _tiempoSimS = 0;
    _tiempoRealS = 0;
    return const ResultadoCapa3(ok: true);
  }

  ResultadoCapa3 completarReescaneoParada() {
    if (_estadoRuta != EstadoRutaOperacional.reescaneoParada) {
      return const ResultadoCapa3(ok: false, motivo: 'estado_invalido');
    }
    _progresoPasadaM = _largoM;
    _paradaConfigurada = true;
    _rutaAprendida = RutaAprendidaOperacional(
      tipoRuta: TipoRutaOperacional.cerrada,
      largoM: _largoM,
      paradaConfigurada: true,
      paradaNombre: _paradaNombre,
      dobleEscaneo: false,
    );
    _estadoRuta = EstadoRutaOperacional.operacionConParada;
    return const ResultadoCapa3(ok: true);
  }

  bool detectarObstaculo() {
    if (_estadoRuta != EstadoRutaOperacional.operacionBucle &&
        _estadoRuta != EstadoRutaOperacional.operacionConParada) {
      return false;
    }
    _estadoPrevioPausa = _estadoRuta;
    _estadoRuta = EstadoRutaOperacional.pausaObstaculo;
    return true;
  }

  bool despejarObstaculo() {
    if (_estadoRuta != EstadoRutaOperacional.pausaObstaculo) return false;
    _estadoRuta = _estadoPrevioPausa ??
        (_paradaConfigurada
            ? EstadoRutaOperacional.operacionConParada
            : EstadoRutaOperacional.operacionBucle);
    _estadoPrevioPausa = null;
    return true;
  }

  /// Prioridad absoluta del MPU-6050: fuerza `ERROR_SEGURIDAD` y pasa pedidos
  /// en tránsito a `CANCELACION_SEGURA` preservando `_rutaAprendida`.
  void dispararAlertaMpu6050(AlertaMpu6050 tipo) {
    _alertaMpu = tipo;
    _estadoPrevioPausa = null;
    _estadoRuta = EstadoRutaOperacional.errorSeguridad;
    if (_estadoPedido == EstadoPedidoOperacional.enTransito) {
      _estadoPedido = EstadoPedidoOperacional.cancelacionSegura;
    }
  }

  bool iniciarRecuperacionManual() {
    if (_estadoRuta != EstadoRutaOperacional.errorSeguridad) return false;
    _estadoRuta = EstadoRutaOperacional.recuperacionManual;
    return true;
  }

  bool completarRecuperacionManual({bool resetearRuta = false}) {
    if (_estadoRuta != EstadoRutaOperacional.recuperacionManual) return false;
    _alertaMpu = null;
    if (_estadoPedido == EstadoPedidoOperacional.cancelacionSegura) {
      _estadoPedido = EstadoPedidoOperacional.sinPedido;
      _pedidoActivo = null;
    }
    if (resetearRuta) {
      _rutaAprendida = null;
      _usosCompletados = 0;
      _estadoRuta = EstadoRutaOperacional.sinRuta;
      return true;
    }
    if (_rutaAprendida != null) {
      _estadoRuta = _paradaConfigurada
          ? EstadoRutaOperacional.operacionConParada
          : EstadoRutaOperacional.operacionBucle;
    } else {
      _estadoRuta = EstadoRutaOperacional.sinRuta;
    }
    return true;
  }

  // ---------------------------------------------------- Máquina de Pedidos
  ResultadoCapa3 solicitarPedido({
    required String paradaId,
    bool conCarga = true,
    String componente = 'Kit de laboratorio',
    String? requestId,
  }) {
    if (!puedeSolicitarPedido) {
      return const ResultadoCapa3(
        ok: false,
        motivo: 'ruta_sin_parada_o_no_operativa',
      );
    }
    _contadorPedidos++;
    _pedidoActivo = PedidoOperacional(
      requestId: requestId ?? 'req-${_contadorPedidos.toString().padLeft(3, '0')}',
      paradaId: paradaId.trim().isEmpty ? _paradaNombre : paradaId.trim(),
      conCarga: conCarga,
      componente: componente,
    );
    _estadoPedido = EstadoPedidoOperacional.solicitado;
    return const ResultadoCapa3(ok: true);
  }

  ResultadoCapa3 despacharPedido() {
    if (_estadoPedido != EstadoPedidoOperacional.solicitado || !puedeMover) {
      return const ResultadoCapa3(ok: false, motivo: 'no_puede_despachar');
    }
    _estadoPedido = EstadoPedidoOperacional.enTransito;
    return const ResultadoCapa3(ok: true);
  }

  /// `CANCELACION_SEGURA`: detiene el pedido sin borrar `_rutaAprendida`.
  ResultadoCapa3 cancelarPedidoSeguro({String motivo = 'cancelado_usuario'}) {
    if (_estadoPedido == EstadoPedidoOperacional.solicitado) {
      _pedidoActivo = null;
      _estadoPedido = EstadoPedidoOperacional.sinPedido;
      return ResultadoCapa3(ok: true, motivo: motivo);
    }
    if (_estadoPedido == EstadoPedidoOperacional.enTransito) {
      _estadoPedido = EstadoPedidoOperacional.cancelacionSegura;
      return ResultadoCapa3(ok: true, motivo: motivo);
    }
    return const ResultadoCapa3(ok: false, motivo: 'sin_pedido_cancelable');
  }

  bool confirmarDetencionCancelacion() {
    if (_estadoPedido != EstadoPedidoOperacional.cancelacionSegura) return false;
    _pedidoActivo = null;
    _estadoPedido = EstadoPedidoOperacional.sinPedido;
    return true;
  }

  bool completarEntregaPedido() {
    if (_estadoPedido != EstadoPedidoOperacional.enTransito) return false;
    _estadoPedido = EstadoPedidoOperacional.entregado;
    return true;
  }

  bool cerrarEntregaPedido() {
    if (_estadoPedido != EstadoPedidoOperacional.entregado) return false;
    _pedidoActivo = null;
    _estadoPedido = EstadoPedidoOperacional.sinPedido;
    return true;
  }

  // -------------------------------------- Recepción MQTT (anti-obsoletos)
  /// Procesa `rutas/estado` (`retained: true`), descartando mensajes obsoletos
  /// cuyo `timestamp` sea menor o igual al último aplicado.
  bool procesarRutasEstadoJson(Map<String, dynamic> json) {
    final int ts = (json['timestamp'] is num)
        ? (json['timestamp'] as num).round()
        : 0;
    if (ts > 0 && ts <= _ultimoTimestampRutasMs) return false;
    final EstadoRutaOperacional? nuevoEstado =
        EstadoRutaOperacional.desdeClave(json['estado_ruta']?.toString());
    if (nuevoEstado == null) return false;
    if (ts > 0) _ultimoTimestampRutasMs = ts;
    if (json['tipo_ruta'] is String) {
      _tipoRuta = TipoRutaOperacional.desdeClave(json['tipo_ruta'] as String);
    }
    _estadoRuta = nuevoEstado;
    if (json['parada_configurada'] is bool) {
      _paradaConfigurada = json['parada_configurada'] as bool;
    }
    if (json['usos_completados'] is num) {
      _usosCompletados = (json['usos_completados'] as num).round();
    }
    return true;
  }

  /// Procesa `pedidos/estado` (`retained: true`), descartando mensajes obsoletos.
  bool procesarPedidosEstadoJson(Map<String, dynamic> json) {
    final int ts = (json['timestamp'] is num)
        ? (json['timestamp'] as num).round()
        : 0;
    if (ts > 0 && ts <= _ultimoTimestampPedidosMs) return false;
    final EstadoPedidoOperacional? nuevoEstado =
        EstadoPedidoOperacional.desdeClave(json['estado_pedido']?.toString());
    if (nuevoEstado == null) return false;
    if (ts > 0) _ultimoTimestampPedidosMs = ts;
    _estadoPedido = nuevoEstado;
    final String? reqId = json['request_id']?.toString();
    if (nuevoEstado == EstadoPedidoOperacional.sinPedido) {
      _pedidoActivo = null;
    } else if (reqId != null && reqId.isNotEmpty) {
      _pedidoActivo = PedidoOperacional(
        requestId: reqId,
        paradaId: _paradaNombre.isNotEmpty ? _paradaNombre : 'Parada 1',
        conCarga: true,
      );
    }
    return true;
  }

  /// Procesa telemetría QoS 0 de `sensores/inercial` (MPU-6050).
  ///
  /// **Blindaje fail-safe (disparo dual):** si `alerta != null`, fuerza
  /// `ERROR_SEGURIDAD` de inmediato; si `alerta == null`, **nunca** limpia un
  /// `ERROR_SEGURIDAD` ni `RECUPERACION_MANUAL` activo (solo la recuperación
  /// manual explícita puede despejarlo).
  void procesarSensoresInercialJson(Map<String, dynamic> json) {
    final LecturaInercial lectura = LecturaInercial.fromJson(json);
    _ultimaLecturaInercial = lectura;
    if (lectura.alerta != null) {
      dispararAlertaMpu6050(lectura.alerta!);
    }
  }

  /// Procesa alerta QoS 2 de MPU-6050 (`impacto|inclinacion|atascamiento`).
  bool procesarAlertaMpuJson(Map<String, dynamic> json) {
    final AlertaMpu6050? alerta = AlertaMpu6050.desdeClave(
      (json['alerta'] ?? json['tipo'])?.toString(),
    );
    if (alerta == null) return false;
    dispararAlertaMpu6050(alerta);
    return true;
  }

  static double _r2(double x) => (x * 100).roundToDouble() / 100;
}
