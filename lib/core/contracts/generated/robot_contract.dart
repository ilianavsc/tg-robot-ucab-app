// Sincronizado manualmente desde ilianavsc/tg-robot-ucab-portfolio @ e505cfda4b1eef84aba2a1d00b50015a2a5d3967.
// Fuente de verdad: specs/mqtt/contract.json (v2.0.0) y specs/pista_canonica.json.
// Trazabilidad del SHA en lib/core/contracts/source-lock.json; validado por test/contrato_sync_test.dart.
// Consumo 100 % offline (sin descargas por red en runtime).

/// Metadatos de un tópico MQTT del contrato canónico.
final class MqttTopicMeta {
  const MqttTopicMeta({
    required this.ruta,
    required this.qos,
    required this.retained,
    required this.direccion,
  });

  final String ruta;
  final int qos;
  final bool retained;

  /// Dirección del flujo: `'robot->app'` o `'app->robot'`.
  final String direccion;
}

abstract final class RobotMqttContract {
  static const String version = '2.0.0';
  static const String schemaVersion = '2.0.0';
  static const String prefijo = 'ucab-tg-sf/robot';

  // Tópicos base (HIL + Simuladores P01–P04)
  static const String topicoEstado = 'ucab-tg-sf/robot/estado';
  static const String topicoUltrasonido = 'ucab-tg-sf/robot/ultrasonido';
  static const String topicoOrdenes = 'ucab-tg-sf/robot/ordenes';
  static const String topicoAck = 'ucab-tg-sf/robot/ordenes/ack';
  static const String topicoAlertas = 'ucab-tg-sf/robot/alertas';
  static const String topicoConexion = 'ucab-tg-sf/robot/conexion';

  // Tópicos Capa 3 Operacional + MPU-6050 (v2.0.0)
  static const String topicoRutasEstado = 'ucab-tg-sf/robot/rutas/estado';
  static const String topicoRutasEscaneo = 'ucab-tg-sf/robot/rutas/escaneo';
  static const String topicoRutasReposicionamiento =
      'ucab-tg-sf/robot/rutas/reposicionamiento';
  static const String topicoPedidosSolicitud =
      'ucab-tg-sf/robot/pedidos/solicitud';
  static const String topicoPedidosEstado = 'ucab-tg-sf/robot/pedidos/estado';
  static const String topicoPedidosCancelacion =
      'ucab-tg-sf/robot/pedidos/cancelacion';
  static const String topicoSensoresInercial =
      'ucab-tg-sf/robot/sensores/inercial';

  static const Map<String, String> topicosCapa3 = <String, String>{
    'rutas_estado': topicoRutasEstado,
    'rutas_escaneo': topicoRutasEscaneo,
    'rutas_reposicionamiento': topicoRutasReposicionamiento,
    'pedidos_solicitud': topicoPedidosSolicitud,
    'pedidos_estado': topicoPedidosEstado,
    'pedidos_cancelacion': topicoPedidosCancelacion,
    'sensores_inercial': topicoSensoresInercial,
  };

  /// Metadatos completos (`ruta`, `qos`, `retained`, `direccion`) de los 13 tópicos.
  static const Map<String, MqttTopicMeta> topicosMeta = <String, MqttTopicMeta>{
    'estado': MqttTopicMeta(
      ruta: topicoEstado,
      qos: 0,
      retained: false,
      direccion: 'robot->app',
    ),
    'ultrasonido': MqttTopicMeta(
      ruta: topicoUltrasonido,
      qos: 0,
      retained: false,
      direccion: 'robot->app',
    ),
    'ordenes': MqttTopicMeta(
      ruta: topicoOrdenes,
      qos: 1,
      retained: false,
      direccion: 'app->robot',
    ),
    'ack': MqttTopicMeta(
      ruta: topicoAck,
      qos: 1,
      retained: false,
      direccion: 'robot->app',
    ),
    'alertas': MqttTopicMeta(
      ruta: topicoAlertas,
      qos: 2,
      retained: false,
      direccion: 'robot->app',
    ),
    'conexion': MqttTopicMeta(
      ruta: topicoConexion,
      qos: 1,
      retained: true,
      direccion: 'robot->app',
    ),
    'rutas_estado': MqttTopicMeta(
      ruta: topicoRutasEstado,
      qos: 1,
      retained: true,
      direccion: 'robot->app',
    ),
    'rutas_escaneo': MqttTopicMeta(
      ruta: topicoRutasEscaneo,
      qos: 1,
      retained: false,
      direccion: 'app->robot',
    ),
    'rutas_reposicionamiento': MqttTopicMeta(
      ruta: topicoRutasReposicionamiento,
      qos: 1,
      retained: false,
      direccion: 'app->robot',
    ),
    'pedidos_solicitud': MqttTopicMeta(
      ruta: topicoPedidosSolicitud,
      qos: 1,
      retained: false,
      direccion: 'app->robot',
    ),
    'pedidos_estado': MqttTopicMeta(
      ruta: topicoPedidosEstado,
      qos: 1,
      retained: true,
      direccion: 'robot->app',
    ),
    'pedidos_cancelacion': MqttTopicMeta(
      ruta: topicoPedidosCancelacion,
      qos: 1,
      retained: false,
      direccion: 'app->robot',
    ),
    'sensores_inercial': MqttTopicMeta(
      ruta: topicoSensoresInercial,
      qos: 0,
      retained: false,
      direccion: 'robot->app',
    ),
  };

  static const int qosEstado = 0;
  static const int qosUltrasonido = 0;
  static const int qosOrdenes = 1;
  static const int qosAck = 1;
  static const int qosAlertas = 2;
  static const int qosConexion = 1;
  static const int qosRutas = 1;
  static const int qosPedidos = 1;
  static const int qosSensoresInercial = 0;

  static const int ackTimeoutMs = 5000;
  static const int manualFailSafeMs = 5000;
  static const int telemetriaIntervaloMs = 1500;
  static const int keepAliveS = 15;

  /// Patrones de tópicos a los que aplica la trazabilidad Capa 3 (excluye QoS 0 continuo).
  static const List<String> trazabilidadAplicaA = <String>[
    'rutas_*',
    'pedidos_*',
  ];

  /// Campos obligatorios de trazabilidad y deduplicación para comandos/eventos
  /// de Capa 3 (`rutas_*`, `pedidos_*`). No aplican a telemetría continua QoS 0
  /// (`estado`, `ultrasonido`, `sensores_inercial`).
  static const List<String> trazabilidadCamposObligatorios = <String>[
    'message_id',
    'request_id',
    'sequence',
    'timestamp',
    'schema_version',
  ];

  /// Regla de deduplicación de comandos y correlación de pedidos (Capa 3).
  static const String trazabilidadDeduplicacion =
      'message_id + sequence monotónica por emisor; request_id correlaciona el ciclo de vida de cada pedido.';

  static const List<String> comandosValidos = <String>[
    'adelante',
    'atras',
    'izquierda',
    'derecha',
    'frenar',
    'auto',
  ];

  static const List<String> camposEstadoFisicoHIL = <String>[
    'n',
    'estado',
    'bateria',
    'bateria_v',
    'ordenes',
    'linea_mm',
    'v_izq',
    'v_der',
    'parada',
    't',
  ];

  static const List<String> camposEstadoExclusivosSimuladorP04 = <String>[
    'progreso_m',
    'largo_m',
    'sensores',
  ];

  // Capa 3 Operacional (alineada 1:1 con P05/capa3_operacional.js)
  static const List<String> estadosRuta = <String>[
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
  ];

  static const List<String> estadosPedido = <String>[
    'SIN_PEDIDO',
    'SOLICITADO',
    'EN_TRANSITO',
    'CANCELACION_SEGURA',
    'ENTREGADO',
  ];

  static const List<String> alertasMpu6050 = <String>[
    'impacto',
    'inclinacion',
    'atascamiento',
  ];

  static const List<String> movimientoBloqueadoEnEstados = <String>[
    'ESPERA_REPOSICION',
    'ERROR_SEGURIDAD',
    'RECUPERACION_MANUAL',
  ];

  static const List<String> camposSensoresInercial = <String>[
    'pitch',
    'roll',
    'acel_g',
    'alerta',
    'timestamp',
    'schema_version',
  ];
}

abstract final class RobotTrackContract {
  static const double longitudCanonicaM = 9.0;
  static const double longitudHistoricaAM = 8.05;
  static const int anchoCintaMm = 19;
  static const int rssiDeteccionDbm = -80;
  static const int rssiLlegadaDbm = -52;

  /// Puntos de control funcionales de la especificación canónica (HEADING_HOLD, REACQUIRE_LINE, WAIT_BEACON).
  static const List<double> puntosControlFuncionalesCanonicosM = <double>[
    3.0,
    4.5,
    7.5,
  ];

  /// Puntos de control equitativos en tercios (L/3, 2L/3, L) usados en P04, P05 y app.
  static const List<double> terciosEquitativosPistaAM = <double>[
    2.68,
    5.37,
    8.05,
  ];
  static const List<double> terciosEquitativosPistaBM = <double>[
    3.0,
    6.0,
    9.0,
  ];
}
