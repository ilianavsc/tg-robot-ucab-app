import 'dart:math' as math;
import 'dart:ui' show Offset, Path, Rect;

/// Geometría física de una pista del laboratorio.
///
/// * [circuitoCerrado]: recorrido en lazo cerrado (el final conecta con el inicio).
/// * [lineal]: recorrido abierto en línea recta de extremo a extremo.
enum TipoGeometriaPista {
  circuitoCerrado('circuito_cerrado', 'Circuito cerrado'),
  lineal('lineal', 'Lineal');

  const TipoGeometriaPista(this.clave, this.etiqueta);

  final String clave;
  final String etiqueta;
}

/// Puntos de control equitativos en tercios del largo total (alineado con P05):
/// `PC1 = L/3`, `PC2 = 2·L/3`, `PC3 = L`.
List<double> puntosControlEquitativos(double largoM) {
  final double l = largoM > 0 ? largoM : largoCanonicoM;
  final double tercio = l / 3;
  return <double>[
    double.parse(tercio.toStringAsFixed(2)),
    double.parse((tercio * 2).toStringAsFixed(2)),
    double.parse(l.toStringAsFixed(2)),
  ];
}

/// Largo del recorrido canónico (m), `specs/pista_canonica.json`.
const double largoCanonicoM = 9.0;

/// Largo del circuito histórico de SIM1 (Pista A, m).
const double largoPistaAM = 8.05;

/// Puntos de control de la pista canónica (m): PC1 inicio del tramo sin
/// línea, PC2 reenganche de línea y PC3 detección de la baliza B2
/// (`specs/pista_canonica.json`).
const List<double> puntosControlCanonicosM = <double>[3.0, 4.5, 7.5];

/// Límites de los tramos T1–T4 de la pista canónica (m).
const List<double> limitesTramosCanonicosM = <double>[0.0, 3.0, 4.5, 7.5, 9.0];

/// Puntos de control de una pista de [largoM] metros. Con el largo canónico
/// son exactamente 3,0 / 4,5 / 7,5 m; con otro largo se escalan en la misma
/// proporción (la especificación solo define estaciones para la canónica).
List<double> puntosControlPara(double largoM) {
  if ((largoM - largoCanonicoM).abs() < 1e-9) {
    return List<double>.of(puntosControlCanonicosM);
  }
  return <double>[
    for (final double pc in puntosControlCanonicosM)
      double.parse((pc / largoCanonicoM * largoM).toStringAsFixed(2)),
  ];
}

/// Geometría de una pista cerrada, muestreada cada [paso] metros, con las
/// mismas coordenadas que el Simulador 1 (x a lo ancho, y = Z de SIM1) y el
/// mismo convenio de dibujo que SIM2 (y hacia arriba en pantalla).
///
/// * `historicaA()`: circuito de 8,05 m (Catmull-Rom por los puntos de
///   control de SIM1, `pista.js · CTRL_A`).
/// * `canonica()`: Pasillo UCAB de 9,000 m (rectas y arcos de radio 0,27 m,
///   `pista.js · trazoB`), sobre el que caen T1–T4 y PC1–PC3.
/// * `escalada(L)`: la canónica escalada a otro largo (pistas nuevas).
class TrazadoPista {
  TrazadoPista._(
    this.id,
    this.puntosM,
    this.paso, {
    this.cerrada = true,
    double? largoM,
  }) : largoM = largoM ?? puntosM.length * paso;

  /// Distancia entre muestras (m), igual que SIM1 (5 mm).
  static const double pasoSim1 = 0.005;

  final String id;

  /// Muestras del trazado (m). Si [cerrada] es `true`, la última une con la primera.
  final List<Offset> puntosM;
  final double paso;

  /// `true` para circuito cerrado; `false` para pista lineal abierta.
  final bool cerrada;

  /// Largo del trazado (m).
  final double largoM;

  TipoGeometriaPista get geometria => cerrada
      ? TipoGeometriaPista.circuitoCerrado
      : TipoGeometriaPista.lineal;

  static TrazadoPista? _a;
  static TrazadoPista? _b;

  /// Pista A · circuito histórico de SIM1 (≈ 8,05 m).
  factory TrazadoPista.historicaA() => _a ??= TrazadoPista._(
    'A',
    _remuestrear(_catmull(_ctrlA), pasoSim1),
    pasoSim1,
  );

  /// Pista canónica · Pasillo UCAB (9,000 m).
  factory TrazadoPista.canonica() =>
      _b ??= TrazadoPista._('B', _trazoB(), pasoSim1);

  /// Forma canónica escalada a [largoM] metros.
  factory TrazadoPista.escalada(double largoM, {String id = 'B*'}) {
    final TrazadoPista b = TrazadoPista.canonica();
    final double k = largoM / b.largoM;
    return TrazadoPista._(id, <Offset>[
      for (final Offset p in b.puntosM) p * k,
    ], b.paso * k);
  }

  /// Pista lineal abierta de [largoM] metros (inicio a la izquierda, fin a la derecha).
  factory TrazadoPista.lineal(double largoM, {String id = 'LIN'}) {
    final double l = largoM > 0 ? largoM : largoCanonicoM;
    final int tramos = math.max(20, (l / pasoSim1).round());
    final double pasoReal = l / tramos;
    final double mitad = l / 2;
    return TrazadoPista._(
      id,
      <Offset>[
        for (int i = 0; i <= tramos; i++) Offset(-mitad + i * pasoReal, 0),
      ],
      pasoReal,
      cerrada: false,
      largoM: l,
    );
  }

  /// Trazado de una pista del catálogo: respeta [geometria] (`lineal` vs
  /// `circuitoCerrado`). Para circuito cerrado, la Pista A usa el circuito
  /// histórico y el resto la forma canónica (escalada si mide otro largo).
  factory TrazadoPista.paraPista(
    String? id,
    double? largoM, {
    TipoGeometriaPista geometria = TipoGeometriaPista.circuitoCerrado,
  }) {
    final double l = largoM ?? largoCanonicoM;
    if (geometria == TipoGeometriaPista.lineal) {
      return TrazadoPista.lineal(l, id: id ?? 'LIN');
    }
    if (id == 'A') return TrazadoPista.historicaA();
    if ((l - largoCanonicoM).abs() < 1e-6) return TrazadoPista.canonica();
    return TrazadoPista.escalada(l, id: id ?? 'B*');
  }

  int _indice(double s) {
    final int n = puntosM.length;
    final int k = (s / paso).round();
    if (!cerrada) return k.clamp(0, n - 1);
    return ((k % n) + n) % n;
  }

  /// Punto (m) a [s] metros de la salida, en el sentido de marcha.
  Offset puntoEn(double s) => puntosM[_indice(s)];

  /// Rumbo (rad, antihorario desde +x) en [s].
  double rumboEn(double s) {
    final Offset a = puntoEn(s - 0.05);
    final Offset b = puntoEn(s + 0.05);
    return math.atan2(b.dy - a.dy, b.dx - a.dx);
  }

  /// Rectángulo que encierra el circuito (m).
  Rect get caja {
    double x0 = double.infinity, x1 = -double.infinity;
    double y0 = double.infinity, y1 = -double.infinity;
    for (final Offset p in puntosM) {
      x0 = math.min(x0, p.dx);
      x1 = math.max(x1, p.dx);
      y0 = math.min(y0, p.dy);
      y1 = math.max(y1, p.dy);
    }
    return Rect.fromLTRB(x0, y0, x1, y1);
  }

  /// Radio de curva mínimo (m) entre [desdeM] y [hastaM]; `infinity` si el
  /// tramo es recto.
  double radioMinimoEntre(double desdeM, double hastaM) {
    double r = double.infinity;
    for (double s = desdeM; s <= hastaM + 1e-9; s += paso) {
      final Offset a = puntoEn(s - 0.05);
      final Offset b = puntoEn(s);
      final Offset c = puntoEn(s + 0.05);
      final double cruz =
          ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx)).abs();
      if (cruz < 1e-12) continue;
      final double ab = (b - a).distance, bc = (c - b).distance;
      final double ac = (c - a).distance;
      r = math.min(r, ab * bc * ac / (2 * cruz));
    }
    return r;
  }
}

// ------------------------------------------------------------ Pista A (SIM1)

const List<Offset> _ctrlA = <Offset>[
  Offset(-1.0, -0.62),
  Offset(0.0, -0.62),
  Offset(0.9, -0.62),
  Offset(1.4, -0.48),
  Offset(1.62, -0.05),
  Offset(1.42, 0.42),
  Offset(0.95, 0.58),
  Offset(0.55, 0.36),
  Offset(0.25, 0.04),
  Offset(-0.1, 0.06),
  Offset(-0.4, 0.36),
  Offset(-0.85, 0.58),
  Offset(-1.32, 0.5),
  Offset(-1.5, 0.12),
  Offset(-1.42, -0.3),
];

List<Offset> _catmull(List<Offset> c) {
  final List<Offset> fino = <Offset>[];
  final int n = c.length;
  double f(double a, double b, double cc, double d, double t) {
    final double t2 = t * t, t3 = t2 * t;
    return 0.5 *
        (2 * b +
            (-a + cc) * t +
            (2 * a - 5 * b + 4 * cc - d) * t2 +
            (-a + 3 * b - 3 * cc + d) * t3);
  }

  for (int i = 0; i < n; i++) {
    final Offset p0 = c[(i - 1 + n) % n], p1 = c[i];
    final Offset p2 = c[(i + 1) % n], p3 = c[(i + 2) % n];
    for (int k = 0; k < 400; k++) {
      final double t = k / 400;
      fino.add(
        Offset(
          f(p0.dx, p1.dx, p2.dx, p3.dx, t),
          f(p0.dy, p1.dy, p2.dy, p3.dy, t),
        ),
      );
    }
  }
  return fino;
}

/// Remuestreo por longitud, un punto cada [paso] (igual que `trazoA` de SIM1).
List<Offset> _remuestrear(List<Offset> fino, double paso) {
  final List<Offset> r = <Offset>[fino.first];
  double acc = 0;
  for (int i = 1; i <= fino.length; i++) {
    final Offset a = fino[i - 1];
    final Offset b = fino[i % fino.length];
    double seg = (b - a).distance;
    double ax = a.dx, ay = a.dy;
    while (acc + seg >= paso) {
      final double k = (paso - acc) / seg;
      ax += (b.dx - ax) * k;
      ay += (b.dy - ay) * k;
      seg = (b - Offset(ax, ay)).distance;
      acc = 0;
      r.add(Offset(ax, ay));
    }
    acc += seg;
  }
  r.removeLast();
  return r;
}

// ------------------------------------------------- Pista canónica (SIM1 · B)

const double _radioB = 0.27; // radio de las curvas
const double _primerRectoB = 1.5;
const double _rectoAntesChicaneB = 0.9;

/// Segmento de tortuga: recto de largo [l] o arco de ángulo [ang] (rad, + a
/// la izquierda) con radio [_radioB].
class _Seg {
  const _Seg.recto(double this.l) : ang = null;
  const _Seg.arco(double this.ang) : l = null;
  final double? l;
  final double? ang;
  double get largo => l ?? ang!.abs() * _radioB;
}

/// Recorre [segs] desde el origen con rumbo +x; si [puntos] no es `null`
/// añade una muestra cada [paso] metros. Devuelve el punto final.
Offset _tortuga(List<_Seg> segs, {List<Offset>? puntos, double paso = 0}) {
  double x = 0, z = 0, h = 0, s = 0;
  int k = 0;
  for (final _Seg g in segs) {
    final double len = g.largo;
    final double sg = g.ang == null ? 1 : (g.ang! < 0 ? -1 : 1);
    final double cx = x - math.sin(h) * _radioB * sg;
    final double cz = z + math.cos(h) * _radioB * sg;
    if (puntos != null) {
      while (k * paso < s + len - 1e-9) {
        final double d = k * paso - s;
        if (g.l != null) {
          puntos.add(Offset(x + math.cos(h) * d, z + math.sin(h) * d));
        } else {
          final double a = d / _radioB * sg;
          puntos.add(
            Offset(
              cx + math.sin(h + a) * _radioB * sg,
              cz - math.cos(h + a) * _radioB * sg,
            ),
          );
        }
        k++;
      }
    }
    if (g.l != null) {
      x += math.cos(h) * len;
      z += math.sin(h) * len;
    } else {
      h += g.ang!;
      x = cx + math.sin(h) * _radioB * sg;
      z = cz - math.cos(h) * _radioB * sg;
    }
    s += len;
  }
  return Offset(x, z);
}

List<Offset> _trazoB() {
  const List<_Seg> chicane = <_Seg>[
    _Seg.arco(math.pi / 4),
    _Seg.arco(-math.pi / 2),
    _Seg.arco(math.pi / 4),
  ];
  final double chiL = chicane.fold(0.0, (double a, _Seg g) => a + g.largo);
  final double dxChi = _tortuga(chicane).dx;
  // recta larga: cierra el circuito en 9,0 m
  final double b = (largoCanonicoM - 2 * math.pi * _radioB + dxChi - chiL) / 2;
  final double e = b - _primerRectoB - dxChi - _rectoAntesChicaneB;
  final List<_Seg> segs = <_Seg>[
    const _Seg.recto(_primerRectoB),
    const _Seg.arco(math.pi),
    _Seg.recto(b),
    const _Seg.arco(math.pi),
    const _Seg.recto(_rectoAntesChicaneB),
    ...chicane,
    _Seg.recto(e),
  ];
  final List<Offset> pts = <Offset>[];
  _tortuga(segs, puntos: pts, paso: TrazadoPista.pasoSim1);
  // centra el trazo (como SIM1)
  double x0 = double.infinity, x1 = -double.infinity;
  double z0 = double.infinity, z1 = -double.infinity;
  for (final Offset p in pts) {
    x0 = math.min(x0, p.dx);
    x1 = math.max(x1, p.dx);
    z0 = math.min(z0, p.dy);
    z1 = math.max(z1, p.dy);
  }
  final Offset c = Offset((x0 + x1) / 2, (z0 + z1) / 2);
  return <Offset>[for (final Offset p in pts) p - c];
}

/// Proyecta [t] dentro de [area] (px) conservando la forma: misma escala en
/// x e y, centrado y con y hacia arriba (igual que el lienzo de SIM2). El
/// camino empieza en la salida (s = 0) y sigue el sentido de marcha.
Path caminoEnLienzo(TrazadoPista t, Rect area, {int cada = 4}) {
  final Rect b = t.caja;
  final double esc = math.min(
    area.width / math.max(b.width, 1e-6),
    area.height / math.max(b.height, 1e-6),
  );
  Offset a(Offset m) => Offset(
    area.center.dx + (m.dx - b.center.dx) * esc,
    area.center.dy - (m.dy - b.center.dy) * esc,
  );
  final Path p = Path();
  final Offset p0 = a(t.puntosM.first);
  p.moveTo(p0.dx, p0.dy);
  for (int k = cada; k < t.puntosM.length; k += cada) {
    final Offset q = a(t.puntosM[k]);
    p.lineTo(q.dx, q.dy);
  }
  if (!t.cerrada) {
    final Offset ultimo = a(t.puntosM.last);
    p.lineTo(ultimo.dx, ultimo.dy);
    return p;
  }
  return p..close();
}
