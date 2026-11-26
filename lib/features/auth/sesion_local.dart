import 'package:flutter/foundation.dart';

/// Rol de la sesión local: **User** (usuario estándar) o **Admin**.
enum RolUsuario {
  operador('USER', 'Usuario'),
  administrador('ADMIN', 'Administrador');

  const RolUsuario(this.etiqueta, this.nombre);

  /// Texto corto en mayúsculas para chips y etiquetas.
  final String etiqueta;

  /// Nombre legible del rol.
  final String nombre;
}

/// **Autenticación local (mock).** Guarda en memoria quién entró y con qué rol.
///
/// No hay backend: las cuentas viven en `RegistroUsuarios` (memoria), no se
/// guarda nada en el dispositivo y la sesión se pierde al cerrar la app. Sirve para mostrar el
/// flujo Login → Telemetría → Perfil → Cerrar sesión y para separar la vista de
/// Operador de la de Administrador.
class SesionLocal extends ChangeNotifier {
  RolUsuario? _rol;
  String _usuario = '';
  String _nombre = '';
  bool _demo = false;
  DateTime? _inicio;
  bool _modoDesarrollador = false;

  /// `null` mientras no haya iniciado sesión (se muestra el Login).
  RolUsuario? get rol => _rol;
  bool get activa => _rol != null;

  /// Nombre de usuario con el que se entró (`admin`, `usuario`, ...).
  String get usuario => _usuario;

  /// Nombre para mostrar (`Administrador demo`, `Ana Pérez`, ...).
  String get nombre => _nombre;

  /// `true` si se entró con el botón **Demo** de la pantalla de inicio.
  bool get demo => _demo;

  /// **Modo Desarrollador** (solo Admin): habilita crear cuentas Admin, las
  /// consolas de sensores (telemetría en vivo), el historial de datos y las
  /// herramientas técnicas. Arranca apagado en cada sesión y se apaga al
  /// cerrarla; con un User siempre es `false`.
  bool get modoDesarrollador =>
      _rol == RolUsuario.administrador && _modoDesarrollador;

  /// Enciende o apaga el Modo Desarrollador. Solo tiene efecto con una sesión
  /// de Administrador; devuelve `false` si no se aplicó.
  bool cambiarModoDesarrollador(bool activo) {
    if (_rol != RolUsuario.administrador) return false;
    if (_modoDesarrollador != activo) {
      _modoDesarrollador = activo;
      notifyListeners();
    }
    return true;
  }

  /// `true` si la sesión de Demo está usando la cuenta `Admin (Demo)`.
  bool get demoAdmin => _demo && _rol == RolUsuario.administrador;

  /// **Solo en Modo Demo**: cambia en vivo entre `Admin (Demo)` y
  /// `User (Demo)`. Apaga el Modo Desarrollador al pasar a User. Devuelve
  /// `false` (sin cambios) fuera de la Demo.
  bool cambiarCuentaDemo({required bool admin}) {
    if (!_demo || _rol == null) return false;
    final RolUsuario nuevo = admin
        ? RolUsuario.administrador
        : RolUsuario.operador;
    if (_rol == nuevo) return true;
    _rol = nuevo;
    _usuario = admin ? usuarioAdminDemo : usuarioUserDemo;
    _nombre = admin ? nombreAdminDemo : nombreUserDemo;
    _modoDesarrollador = false;
    notifyListeners();
    return true;
  }

  static const String usuarioAdminDemo = 'admin.demo';
  static const String usuarioUserDemo = 'user.demo';
  static const String nombreAdminDemo = 'Admin (Demo)';
  static const String nombreUserDemo = 'User (Demo)';

  /// Inicia la **Demo** con la cuenta `Admin (Demo)`.
  void iniciarDemo({DateTime? ahora}) => iniciar(
    RolUsuario.administrador,
    usuario: usuarioAdminDemo,
    nombre: nombreAdminDemo,
    demo: true,
    ahora: ahora,
  );

  /// Momento en que se inició la sesión local.
  DateTime? get inicio => _inicio;

  /// Tiempo transcurrido desde el inicio de sesión.
  Duration duracion([DateTime? ahora]) {
    final DateTime? i = _inicio;
    if (i == null) return Duration.zero;
    return (ahora ?? DateTime.now()).difference(i);
  }

  void iniciar(
    RolUsuario rol, {
    required String usuario,
    String? nombre,
    bool demo = false,
    DateTime? ahora,
  }) {
    _rol = rol;
    _usuario = usuario.trim();
    _nombre = (nombre ?? '').trim().isEmpty ? rol.nombre : nombre!.trim();
    _demo = demo;
    _inicio = ahora ?? DateTime.now();
    _modoDesarrollador = false;
    notifyListeners();
  }

  void cerrar() {
    if (_rol == null) return;
    _rol = null;
    _usuario = '';
    _nombre = '';
    _demo = false;
    _inicio = null;
    _modoDesarrollador = false;
    notifyListeners();
  }
}
