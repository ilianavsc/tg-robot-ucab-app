// GENERATED — DO NOT EDIT BY HAND.
// Fuente de verdad: ilianavsc/tg-robot-ucab-portfolio @ 934490fe29b6876f7ac20a9528015a2c3961ccb1
// Archivos origen: specs/mqtt/contract.json (v2.0.0), specs/pista_canonica.json
// Consumo 100 % offline (sin descargas por red en runtime).

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
    't',
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
