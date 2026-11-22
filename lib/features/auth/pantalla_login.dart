import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/mqtt/mqtt_service.dart';
import '../../core/theme/cockpit_theme.dart';
import '../../shared/widgets/pastilla_mqtt.dart';
import '../telemetria/cockpit_ui.dart';
import 'catalogo_pistas.dart';
import 'pantalla_escaneo_pista.dart';
import 'registro_usuarios.dart';
import 'sesion_local.dart';

/// Pantalla de acceso (Stitch v2). Autenticación **local, sin backend**: el
/// usuario y la contraseña se comprueban contra `RegistroUsuarios` (memoria) y
/// el rol sale de la cuenta, no de un selector. También ofrece el Modo Demo
/// (Offline). No hay registro público: solo un Administrador crea operadores.
class PantallaLogin extends StatefulWidget {
  const PantallaLogin({super.key});

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _clave = TextEditingController();
  final CatalogoPistas _catalogoFallback = CatalogoPistas();
  RolUsuario _rolSeleccionado = RolUsuario.operador;
  bool _verClave = false;
  String? _error;

  static const String _accionNuevaPista = '__nueva_pista__';

  CatalogoPistas _catalogo(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<CatalogoPistas>(context, listen: listen);
    } on ProviderNotFoundException {
      return _catalogoFallback;
    }
  }

  @override
  void dispose() {
    _usuario.dispose();
    _clave.dispose();
    _catalogoFallback.dispose();
    super.dispose();
  }

  /// `+ Nueva pista`: crea la pista en modo básico (0 torres, pendiente) y
  /// abre de inmediato el Escaneo y Validación de Pista (Gemelo Digital).
  Future<void> _confirmarEliminarPista(
    CatalogoPistas catalogo,
    PistaLocal pista,
  ) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogCtx) {
        return AlertDialog(
          backgroundColor: CockpitColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CockpitRadius.lg),
            side: BorderSide(
              color: CockpitColors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          title: Text(
            'Eliminar pista',
            style: CockpitText.titleMd.copyWith(color: CockpitColors.onSurface),
          ),
          content: Text(
            '¿Eliminar pista ${pista.nombre}?',
            style: CockpitText.bodyMd.copyWith(
              color: CockpitColors.onSurfaceVariant,
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('pista-eliminar-cancelar'),
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('pista-eliminar-confirmar'),
              style: FilledButton.styleFrom(
                backgroundColor: CockpitColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirmar == true) {
      catalogo.eliminarPista(pista.id);
      if (mounted) setState(() => _error = null);
    }
  }

  Future<void> _mostrarNuevaPista(CatalogoPistas catalogo) async {
    final String? id = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoNuevaPista(catalogo: catalogo),
    );
    if (id == null || !mounted) return;
    setState(() => _error = null);
    await _abrirEscaneo(catalogo, id);
  }

  Future<void> _abrirEscaneo(CatalogoPistas catalogo, String id) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PantallaEscaneoPista(catalogo: catalogo, pistaId: id),
      ),
    );
    if (mounted) setState(() => _error = null);
  }

  void _cambiarRol(RolUsuario rol) {
    if (_rolSeleccionado == rol) return;
    setState(() {
      _rolSeleccionado = rol;
      _error = null;
    });
  }

  void _entrar() {
    final CatalogoPistas catalogo = _catalogo(context, listen: false);
    if (!catalogo.tienePistaActiva) {
      setState(
        () => _error = 'Selecciona o crea una pista antes de iniciar sesión.',
      );
      return;
    }
    if (!catalogo.puedeIniciarSesion(_rolSeleccionado)) {
      setState(
        () => _error =
            'La pista activa está pendiente de escaneo: el Operador necesita '
            'una pista configurada.',
      );
      return;
    }
    final CuentaLocal? cuenta = context.read<RegistroUsuarios>().autenticar(
      _usuario.text,
      _clave.text,
    );
    if (cuenta == null) {
      setState(() => _error = 'Usuario o contraseña incorrectos.');
      return;
    }
    if (cuenta.rol != _rolSeleccionado) {
      setState(
        () => _error =
            'Esta cuenta corresponde al perfil ${cuenta.rol.nombre}.',
      );
      return;
    }
    context.read<SesionLocal>().iniciar(
      cuenta.rol,
      usuario: cuenta.usuario,
      nombre: cuenta.nombre,
    );
  }

  /// Modo Demo directo: entra como el Operador de demostración y arranca la
  /// telemetría simulada de `MqttService` (sin red ni robot).
  void _entrarDemo() {
    // Simula la pista activa (8,05 m la Pista A); sin pista, la canónica.
    context.read<MqttService>().iniciarSimulacion(
      longitudM:
          _catalogo(context, listen: false).activa?.longitudM ??
          largoCanonicoM,
    );
    context.read<SesionLocal>().iniciar(
      RolUsuario.operador,
      usuario: 'user',
      nombre: 'Operador demo',
      demo: true,
    );
  }

  InputDecoration _decoracion({
    required IconData icono,
    String? hint,
    Widget? sufijo,
    String? error,
  }) {
    OutlineInputBorder borde(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CockpitRadius.md),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      filled: true,
      fillColor: CockpitColors.surfaceLow,
      hintText: hint,
      hintStyle: CockpitText.bodyMd.copyWith(color: CockpitColors.outline),
      errorText: error,
      errorMaxLines: 2,
      prefixIcon: Icon(icono, size: 20, color: CockpitColors.onSurfaceVariant),
      suffixIcon: sufijo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      enabledBorder: borde(
        CockpitColors.outlineVariant.withValues(alpha: 0.55),
      ),
      focusedBorder: borde(CockpitColors.primary),
      errorBorder: borde(CockpitColors.error),
      focusedErrorBorder: borde(CockpitColors.error),
    );
  }

  Widget _etiqueta(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      texto,
      style: CockpitText.labelMd.copyWith(color: CockpitColors.onSurface),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool esAdmin = _rolSeleccionado == RolUsuario.administrador;
    final CatalogoPistas catalogo = _catalogo(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const _Marca(),
                      const SizedBox(height: 24),
                      _SelectorRol(
                        seleccionado: _rolSeleccionado,
                        alCambiar: _cambiarRol,
                      ),
                      const SizedBox(height: 18),
                      _etiqueta('USUARIO'),
                      TextField(
                        key: const Key('login-usuario'),
                        controller: _usuario,
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        style: CockpitText.bodyMd.copyWith(
                          color: CockpitColors.onSurface,
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        decoration: _decoracion(
                          icono: Icons.person_outline,
                          hint: esAdmin ? 'admin' : 'user',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _etiqueta('CONTRASEÑA'),
                      TextField(
                        key: const Key('login-clave'),
                        controller: _clave,
                        obscureText: !_verClave,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _entrar(),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        style: CockpitText.bodyMd.copyWith(
                          color: CockpitColors.onSurface,
                        ),
                        decoration: _decoracion(
                          icono: Icons.lock_outline,
                          hint: '••••••••',
                          error: _error,
                          sufijo: IconButton(
                            tooltip: _verClave
                                ? 'Ocultar contraseña'
                                : 'Mostrar contraseña',
                            icon: Icon(
                              _verClave
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: CockpitColors.onSurfaceVariant,
                            ),
                            onPressed: () =>
                                setState(() => _verClave = !_verClave),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Pressable(
                        child: FilledButton(
                          key: const Key('login-entrar'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            textStyle: const TextStyle(
                              fontFamily: CockpitText.sans,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: catalogo.puedeIniciarSesion(_rolSeleccionado)
                              ? _entrar
                              : null,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text('Iniciar Sesión'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!catalogo.tienePistaActiva)
                        Text(
                          'Selecciona o crea una pista antes de iniciar sesión.',
                          key: const Key('login-aviso-pista'),
                          textAlign: TextAlign.center,
                          style: CockpitText.bodySm.copyWith(
                            color: CockpitColors.warning,
                          ),
                        )
                      else if (!catalogo.activaConfigurada)
                        _AvisoPistaPendiente(
                          nombre: catalogo.activa!.nombre,
                          bloqueaOperador: !esAdmin,
                          alContinuar: () =>
                              _abrirEscaneo(catalogo, catalogo.activaId!),
                        )
                      else
                        Text(
                          'Pista activa: ${catalogo.activa!.nombre} '
                          '(${catalogo.activa!.longitudM.toStringAsFixed(2).replaceAll('.', ',')} m)',
                          key: const Key('login-pista-activa'),
                          textAlign: TextAlign.center,
                          style: CockpitText.bodySm.copyWith(
                            color: CockpitColors.primary,
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Center(child: PastillaMqtt()),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Universidad Católica Andrés Bello · Ingeniería',
                          key: const Key('login-pie'),
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: CockpitText.telemetrySm.copyWith(
                            color: CockpitColors.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 16,
              child: Semantics(
                button: true,
                label: 'Seleccionar pista',
                child: PopupMenuButton<String>(
                  key: const Key('login-pistas'),
                  tooltip: 'Seleccionar pista',
                  offset: const Offset(0, 48),
                  color: CockpitColors.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CockpitRadius.md),
                    side: BorderSide(
                      color: CockpitColors.outlineVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                  onSelected: (String valor) {
                    if (valor == _accionNuevaPista) {
                      _mostrarNuevaPista(catalogo);
                    } else {
                      catalogo.seleccionar(valor);
                      setState(() => _error = null);
                    }
                  },
                  itemBuilder: (BuildContext ctx) {
                    final List<PopupMenuEntry<String>>
                    items = <PopupMenuEntry<String>>[
                      for (final PistaLocal p in catalogo.pistas)
                        PopupMenuItem<String>(
                          key: Key('pista-item-${p.id}'),
                          value: p.id,
                          child: Row(
                            children: <Widget>[
                              Icon(
                                p.id == catalogo.activaId
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 16,
                                color: p.id == catalogo.activaId
                                    ? CockpitColors.primary
                                    : CockpitColors.outline,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      p.nombre,
                                      overflow: TextOverflow.ellipsis,
                                      style: CockpitText.bodySm.copyWith(
                                        color: p.id == catalogo.activaId
                                            ? Colors.white
                                            : CockpitColors.onSurface,
                                        fontWeight: p.id == catalogo.activaId
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    if (p.esCircuitoCerrado)
                                      Text(
                                        p.geometria.etiqueta,
                                        key: Key('pista-tipo-${p.id}'),
                                        style: CockpitText.telemetrySm.copyWith(
                                          fontSize: 10,
                                          color: CockpitColors.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!p.configurada) ...<Widget>[
                                Icon(
                                  Icons.pending_outlined,
                                  key: Key('pista-pendiente-${p.id}'),
                                  size: 14,
                                  color: CockpitColors.warning,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                p.configurada
                                    ? '${p.longitudM.toStringAsFixed(2).replaceAll('.', ',')} m'
                                    : 'pendiente',
                                style: CockpitText.telemetrySm.copyWith(
                                  color: CockpitColors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                key: Key('pista-eliminar-${p.id}'),
                                tooltip: 'Eliminar pista ${p.nombre}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                splashRadius: 16,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: CockpitColors.outline,
                                ),
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _confirmarEliminarPista(catalogo, p);
                                },
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(height: 8),
                      PopupMenuItem<String>(
                        key: const Key('pista-nueva'),
                        value: _accionNuevaPista,
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.add_circle_outline,
                              size: 16,
                              color: CockpitColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '+ Nueva pista',
                              style: CockpitText.bodySm.copyWith(
                                color: CockpitColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                    return items;
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 42,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: ShapeDecoration(
                      color: CockpitColors.surfaceContainer.withValues(
                        alpha: 0.85,
                      ),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: CockpitColors.outlineVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.menu,
                          size: 16,
                          color: CockpitColors.primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Pistas',
                          style: CockpitText.labelMd.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: CockpitColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: Semantics(
                button: true,
                label: 'Entrar en Modo Demo (Offline)',
                child: OutlinedButton.icon(
                  key: const Key('login-demo'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: CockpitColors.surfaceContainer.withValues(
                      alpha: 0.85,
                    ),
                    foregroundColor: CockpitColors.onSurfaceVariant,
                    minimumSize: const Size(44, 42),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: const StadiumBorder(),
                    side: BorderSide(
                      color: CockpitColors.outlineVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                    textStyle: CockpitText.labelMd.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _entrarDemo,
                  icon: const Icon(
                    Icons.science_outlined,
                    size: 16,
                    color: CockpitColors.primary,
                  ),
                  label: const Text('Demo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra deslizadora (segmented toggle) para elegir el perfil de acceso.
class _SelectorRol extends StatelessWidget {
  const _SelectorRol({required this.seleccionado, required this.alCambiar});

  final RolUsuario seleccionado;
  final ValueChanged<RolUsuario> alCambiar;

  @override
  Widget build(BuildContext context) {
    final bool esAdmin = seleccionado == RolUsuario.administrador;
    return Container(
      key: const Key('login-selector-rol'),
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CockpitColors.surfaceLow,
        borderRadius: BorderRadius.circular(CockpitRadius.md),
        border: Border.all(
          color: CockpitColors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double anchoOpcion = constraints.maxWidth / 2;
          return Stack(
            children: <Widget>[
              AnimatedAlign(
                alignment: esAdmin
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: anchoOpcion,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: CockpitColors.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(CockpitRadius.md - 2),
                    border: Border.all(
                      color: CockpitColors.primary.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  _opcion(
                    clave: const Key('rol-operador'),
                    etiqueta: 'Operador',
                    icono: Icons.engineering_outlined,
                    activa: !esAdmin,
                    alTocar: () => alCambiar(RolUsuario.operador),
                  ),
                  _opcion(
                    clave: const Key('rol-administrador'),
                    etiqueta: 'Administrador',
                    icono: Icons.admin_panel_settings_outlined,
                    activa: esAdmin,
                    alTocar: () => alCambiar(RolUsuario.administrador),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _opcion({
    required Key clave,
    required String etiqueta,
    required IconData icono,
    required bool activa,
    required VoidCallback alTocar,
  }) {
    final Color color = activa
        ? CockpitColors.primary
        : CockpitColors.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: activa,
        label: etiqueta,
        child: InkWell(
          key: clave,
          borderRadius: BorderRadius.circular(CockpitRadius.md - 2),
          onTap: alTocar,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CockpitText.labelMd.copyWith(
                      fontSize: 12.5,
                      fontWeight: activa ? FontWeight.w700 : FontWeight.w600,
                      color: activa ? Colors.white : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logotipo y nombre de la app.
class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: CockpitColors.primaryTonal.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(CockpitRadius.xl),
            border: Border.all(
              color: CockpitColors.primary.withValues(alpha: 0.45),
            ),
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(
                Icons.hexagon_outlined,
                size: 40,
                color: CockpitColors.primary,
              ),
              Icon(Icons.explore, size: 18, color: CockpitColors.primary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          const TextSpan(
            children: <InlineSpan>[
              TextSpan(text: 'TG Robot '),
              TextSpan(
                text: 'UCAB',
                style: TextStyle(color: CockpitColors.primary),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: CockpitText.headlineMd.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Autonomous Laboratory AGV',
          style: CockpitText.bodyMd.copyWith(
            color: CockpitColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Aviso cuando la pista activa sigue pendiente de escaneo.
class _AvisoPistaPendiente extends StatelessWidget {
  const _AvisoPistaPendiente({
    required this.nombre,
    required this.bloqueaOperador,
    required this.alContinuar,
  });

  final String nombre;
  final bool bloqueaOperador;
  final VoidCallback alContinuar;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('login-aviso-pendiente'),
      children: <Widget>[
        Text(
          bloqueaOperador
              ? '$nombre está pendiente de escaneo. El Operador solo puede '
                    'entrar con una pista configurada.'
              : '$nombre está pendiente de escaneo (modo Administrador).',
          textAlign: TextAlign.center,
          style: CockpitText.bodySm.copyWith(color: CockpitColors.warning),
        ),
        TextButton.icon(
          key: const Key('login-continuar-escaneo'),
          onPressed: alContinuar,
          icon: const Icon(Icons.radar, size: 18),
          label: const Text('Continuar escaneo'),
        ),
      ],
    );
  }
}

/// Modal compacto para registrar una nueva pista en modo básico. Devuelve el
/// id de la pista creada (pendiente de escaneo) o `null` si se cancela.
class _DialogoNuevaPista extends StatefulWidget {
  const _DialogoNuevaPista({required this.catalogo});

  final CatalogoPistas catalogo;

  @override
  State<_DialogoNuevaPista> createState() => _DialogoNuevaPistaState();
}

class _DialogoNuevaPistaState extends State<_DialogoNuevaPista> {
  final TextEditingController _nombre = TextEditingController();
  final TextEditingController _largo = TextEditingController(text: '9.0');
  TipoGeometriaPista _geometria = TipoGeometriaPista.circuitoCerrado;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _largo.dispose();
    super.dispose();
  }

  InputDecoration _deco(IconData icono, String hint, {String? error}) {
    OutlineInputBorder borde(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(CockpitRadius.md),
      borderSide: BorderSide(color: c),
    );
    return InputDecoration(
      filled: true,
      fillColor: CockpitColors.surfaceLow,
      hintText: hint,
      hintStyle: CockpitText.bodyMd.copyWith(color: CockpitColors.outline),
      errorText: error,
      prefixIcon: Icon(icono, size: 20, color: CockpitColors.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: borde(
        CockpitColors.outlineVariant.withValues(alpha: 0.55),
      ),
      focusedBorder: borde(CockpitColors.primary),
      errorBorder: borde(CockpitColors.error),
      focusedErrorBorder: borde(CockpitColors.error),
    );
  }

  void _guardar() {
    final String nombre = _nombre.text.trim();
    final double? largo = double.tryParse(
      _largo.text.trim().replaceAll(',', '.'),
    );
    if (nombre.isEmpty) {
      setState(() => _error = 'Escribe un nombre.');
      return;
    }
    if (largo == null || largo < 1.0 || largo > 50.0) {
      setState(() => _error = 'Longitud válida: 1,0 a 50,0 m.');
      return;
    }
    final PistaLocal? pista = widget.catalogo.agregarPista(
      nombre: nombre,
      longitudM: largo,
      geometria: _geometria,
    );
    Navigator.of(context).pop(pista?.id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CockpitColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CockpitRadius.lg),
        side: BorderSide(
          color: CockpitColors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      title: Text(
        'Nueva pista',
        style: CockpitText.titleMd.copyWith(color: CockpitColors.onSurface),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                key: const Key('nueva-pista-modo-basico'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CockpitColors.surfaceLow,
                  borderRadius: BorderRadius.circular(CockpitRadius.md),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: CockpitColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Calibración guiada por Administrador · asegura la '
                        'pista sin obstáculos temporales antes de escanear.',
                        style: CockpitText.bodySm.copyWith(
                          color: CockpitColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'TIPO DE PISTA',
                style: CockpitText.labelMd.copyWith(
                  fontSize: 11,
                  color: CockpitColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<TipoGeometriaPista>(
                key: const Key('nueva-pista-tipo'),
                showSelectedIcon: false,
                segments: const <ButtonSegment<TipoGeometriaPista>>[
                  ButtonSegment<TipoGeometriaPista>(
                    value: TipoGeometriaPista.circuitoCerrado,
                    icon: Icon(Icons.loop, size: 16),
                    label: Text(
                      'Circuito cerrado',
                      key: Key('tipo-pista-circuito'),
                    ),
                  ),
                  ButtonSegment<TipoGeometriaPista>(
                    value: TipoGeometriaPista.lineal,
                    icon: Icon(Icons.linear_scale, size: 16),
                    label: Text('Lineal', key: Key('tipo-pista-lineal')),
                  ),
                ],
                selected: <TipoGeometriaPista>{_geometria},
                onSelectionChanged: (Set<TipoGeometriaPista> sel) {
                  if (sel.isNotEmpty) {
                    setState(() => _geometria = sel.first);
                  }
                },
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('nueva-pista-nombre'),
                controller: _nombre,
                autofocus: true,
                textInputAction: TextInputAction.next,
                style: CockpitText.bodyMd.copyWith(
                  color: CockpitColors.onSurface,
                ),
                decoration: _deco(Icons.route_outlined, 'Ej. Pista B'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('nueva-pista-largo'),
                controller: _largo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _guardar(),
                style: CockpitText.bodyMd.copyWith(
                  color: CockpitColors.onSurface,
                ),
                decoration: _deco(
                  Icons.straighten_outlined,
                  'Longitud estimada en metros (ej. 9.0)',
                  error: _error,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('nueva-pista-crear'),
          onPressed: _guardar,
          child: const Text('Crear y escanear'),
        ),
      ],
    );
  }
}
