# robot_ucab_app

App móvil y web (Flutter) del robot de laboratorio UCAB: telemetría, pedidos y alertas por MQTT.

- **App en vivo:** https://ilianavsc.github.io/tg-robot-ucab-app/
- **Portafolio, simuladores (P01–P05), firmware y documentación:** https://ilianavsc.github.io/tg-robot-ucab-portfolio/

## Diseño: versión oscura del portafolio

La interfaz es la **versión oscura nativa de `tg-robot-ucab-portfolio`**: fondo
`#0B0F19`, tarjetas `#111827` con bordes sutiles `#1E293B`, acento cian/turquesa
técnico (`#2DD4BF` / `#06B6D4`), verde de estado y ámbar de alerta. **Inter** para
texto y **JetBrains Mono** para la telemetría; las fuentes van incrustadas en
`assets/fonts/` (licencias OFL), así que la Demo se ve igual sin internet.
Tokens en `lib/core/theme/cockpit_theme.dart`.

## Inicio, Demo y roles

- **Inicio con solo 3 botones:** **Pistas** (gestor de pistas; la **Pista A**
  viene predeterminada), **Login** (tarjeta colapsable: User o Admin, indicando
  sobre qué pista se ingresa) y **Demo**. Fuera de la Demo **no se inicia sesión
  sin una pista seleccionada**.
- **Demo:** entra como **Admin (Demo)** sobre la **Pista C** (lineal, 2
  segmentos), con telemetría simulada y **sin nada de Conexión**. En el Perfil, un
  interruptor cambia en vivo entre **Admin (Demo)** y **User (Demo)**.
- **Operación real:** al iniciar sesión aparece la sección **Conexión** (sin Modo
  Desarrollador). El **mini-mapa está apagado** y no hay operación ni envío de
  órdenes hasta establecer la conexión; luego se enciende con la pista activa.
- **User:** opera la pista (pedidos y mapa limpio). **Admin:** además crea
  usuarios **User** y tiene el interruptor de **Modo Desarrollador**, que habilita
  crear cuentas **Admin**, las **consolas de sensores**, el **historial de datos**
  (sección **DATOS**) y las herramientas técnicas (Controles, Radar, Alertas).
- **Freno Remoto** (Modo Desarrollador) envía `frenar` por MQTT. No es un corte
  eléctrico: no sustituye el interruptor físico.

## Estructura

```
lib/
  main.dart                    # ChangeNotifierProvider + MaterialApp
  core/
    config/                    # configuración (broker, tópicos)
    models/                    # estado, ultrasonido (frente_ok/atras_ok), orden_ack
    alertas/centro_alertas.dart    # P11: motor de alertas (Dart puro, con tests)
    analitica/analitica_sesion.dart # P12: métricas de sesión + CSV (Dart puro)
    exportar/descarga_csv*.dart    # descarga del CSV en Web (portapapeles en nativo)
    demo/simulacion_pista.dart # Modo Demo físico: robot sobre un circuito (PID, batería 3S, obstáculo, órdenes)
    mqtt/mqtt_service.dart     # cliente MQTT + reconexión + Modo Demo + P11/P12
    mqtt/mqtt_client_platform_*.dart  # fábrica por plataforma (TCP vs WebSocket)
    theme/cockpit_theme.dart   # tokens de color, tipografía y ThemeData del Cockpit
  features/
    auth/
      sesion_local.dart        # sesión local (mock, sin backend): rol, usuario y nombre
      registro_usuarios.dart   # RBAC local en memoria: usuario/usuario, admin/admin y operadores creados
      pantalla_login.dart      # Inicio: 3 botones (Pistas, Login colapsable, Demo)
    perfil/
      pantalla_perfil.dart     # Perfil (Operador/Admin): sesión, enlace MQTT, cerrar sesión
      perfil_admin.dart        # solo Admin: usuarios; con Modo Desarrollador: Fail-Safe, consolas, historial, CSV P12
      gestion_usuarios.dart    # solo Admin: crear User (y Admin con Modo Desarrollador), en memoria
      aprendizaje_ruta.dart    # solo Admin: modelo de la pasada de aprendizaje, puntos de control y reducción de cinta (SIL)
      pantalla_aprendizaje_ruta.dart # solo Admin: pasada virtual, ruta guardada y vista previa de la reducción progresiva de cinta
    telemetria/
      telemetria_screen.dart   # armazón: app bar, Conexión (fuera de Demo), 5 secciones técnicas, Freno Remoto
      mapa_pista.dart          # Mapa de Pista: circuito, cono del ultrasonido, misión, destinos y pausa
      pantalla_dashboard.dart  # Mapa de Pista + estado, enlace MQTT, energía 3S, IR, motores, P12
      pantalla_controles.dart  # matriz táctil, Auto, ACK, núcleo de seguridad
      pantalla_radar.dart      # radar polar (radar_hud.dart) y evitación
      pantalla_alertas.dart    # watchdog, activas y registro de eventos (P11)
      alertas_p11.dart         # Banner de Alerta Activa (P11)
      analitica_p12.dart       # Analítica de Sesión + "Exportar Reporte CSV" (P12)
      cockpit_ui.dart          # tarjeta, celda, pastilla, Freno Remoto y demás primitivas
      cockpit_datos.dart       # cálculos derivados (Dart puro, con tests)
    pedidos/                   # (Fase V) crear pedidos y ver ACK
    alertas/                   # (Fase V) notificaciones push de alertas QoS 2
    conexion/                  # acceso a la operación, sección Conexión y mini-mapa apagado
    datos/                     # Modo Desarrollador: consolas de sensores e historial de datos
  shared/widgets/
tool/telemetria_pc.dart        # diagnóstico MQTT por consola (sin Flutter)
```

## Correr en Chrome (demo)

```bash
flutter run -d chrome
```

El cliente web se conecta por WebSocket seguro a `wss://broker.hivemq.com:8884/mqtt`.
En nativo (Android/Windows) se conecta por TCP a `broker.hivemq.com:1883`.

## Pruebas y análisis

```bash
flutter analyze
flutter test        # P11, P12, modelos, Demo, inicio (3 botones), roles, Conexión y Modo Desarrollador
```

## P11 · Centro de Alertas y P12 · Analítica

- **P11** deduce en tiempo real (MQTT/P10 y Modo Demo): parada por obstáculo
  (`frente_cm < 20`), fallo de sensor sin eco (`frente_ok:false`), proximidad
  (20–50 cm) y batería crítica (≤ 10,3 V, ignorando 0,00 V). También escucha
  `ucab-tg-sf/robot/alertas` (QoS 2). Banner rojo/ámbar con "Reconocer".
- **P12** acumula velocidad media/máxima, distancia frontal mínima válida, error
  medio absoluto de línea, paquetes y paradas de emergencia. Se reinicia al
  detener el demo o con "Reiniciar". "Exportar Reporte CSV" descarga el archivo.

## Probar la conexión sin Flutter

```bash
dart run tool/telemetria_pc.dart --simular --seg=15
```
