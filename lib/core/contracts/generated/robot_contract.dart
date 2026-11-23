// GENERATED — DO NOT EDIT BY HAND.
// Fuente de verdad: ilianavsc/tg-robot-ucab-portfolio @ a3dba9eb86062f808cf502d0389b0f6a4b9278d1
// Archivos origen: specs/mqtt/contract.json, specs/pista_canonica.json
// Consumo 100 % offline (sin descargas por red en runtime).

abstract final class RobotMqttContract {
  static const String version = '1.0.0';
  static const String prefijo = 'ucab-tg-sf/robot';

  static const String topicoEstado = 'ucab-tg-sf/robot/estado';
  static const String topicoUltrasonido = 'ucab-tg-sf/robot/ultrasonido';
  static const String topicoOrdenes = 'ucab-tg-sf/robot/ordenes';
  static const String topicoAck = 'ucab-tg-sf/robot/ordenes/ack';
  static const String topicoAlertas = 'ucab-tg-sf/robot/alertas';
  static const String topicoConexion = 'ucab-tg-sf/robot/conexion';

  static const int qosEstado = 0;
  static const int qosUltrasonido = 0;
  static const int qosOrdenes = 1;
  static const int qosAck = 1;
  static const int qosAlertas = 2;
  static const int qosConexion = 1;

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
}

abstract final class RobotTrackContract {
  static const double longitudCanonicaM = 9.0;
  static const double longitudHistoricaAM = 8.05;
  static const int anchoCintaMm = 19;

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
