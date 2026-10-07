# CLAUDE.md

Instrucciones para Claude al trabajar en este repo: app de residentes (iPhone y Apple Watch) de
una plataforma mexicana de acceso y seguridad para fraccionamientos. La fuente es el **brief del
agente iOS (requerimientos 0.4, 45 pantallas)**; aquí está lo esencial y, sobre todo, **lo que falta
por integrar**. Los supuestos tomados están en `DECISIONES.md`: léelo antes de cambiar red, sesión,
firma o mocks, y anota ahí cada supuesto nuevo.

## Reglas de trabajo

- **Prioridad de fuentes:** reglas de negocio > requerimientos (RF/RNF) > maquetas > stack.
  Si algo no está definido (ver "Decisiones abiertas"), pregunta en lugar de decidir.
- **Backend no existe todavía.** Todo va contra `MockServer` (`Core/Mock`) a través de la misma capa
  de red que usará el backend real. No inventes endpoints definitivos: agrega el endpoint en
  `Core/API/API.swift`, su protocolo en `Core/Repositories`, la ruta en `MockServer` y marca los
  campos supuestos en `DECISIONES.md`.
- **Flujo de datos único:** Vista → ViewModel (`@Observable`) → repositorio (protocolo) → `APIClient`
  → interceptores (`DefaultHeaders`, `AuthInterceptor`) → transporte (`MockTransport` / `URLSession`).
  Nunca crear clientes de red en una vista; todo sale de `AppContainer`.
- **Acciones sensibles (RF-67)** se firman con `RequestSigner` (llave P-256 del Secure Enclave con
  `.userPresence`). La biometría nunca es un booleano local. No pongas en la UI frases como
  "te pediremos Face ID" en cada acción: es redundante.
- **Swift 6 estricto**, aislamiento `MainActor` por defecto (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
  Modelos/DTOs/enums auxiliares `nonisolated`; lo que corre fuera del hilo principal es `actor`.
  Delegados de frameworks de Apple (notificaciones, ubicación): métodos `nonisolated` que extraen
  valores `Sendable` y saltan con `Task { @MainActor in … }`; en `UNUserNotificationCenterDelegate`
  usa las variantes con completion handler, no las `async` (truenan fuera del hilo principal).
- **Destino mínimo iOS 17**, con APIs nuevas detrás de `if #available` (Liquid Glass, accesorio de
  la barra de pestañas, `sharedBackgroundVisibility` vía `.sharedBackgroundHidden()`, etc.).
- **Carpetas sincronizadas de Xcode:** los archivos nuevos dentro de `SecurityIslas/` se incluyen
  solos. Targets, capabilities y extensiones nuevas sí requieren Xcode (pídeselo al usuario).
- **No hay compilador de Swift en el contenedor de la nube.** Revisa a mano llaves/paréntesis y
  tipos; pide al usuario compilar en Xcode cuando el cambio sea delicado.
- **Git:** el usuario trabaja directo en `main` ("sube directo"). Antes de subir:
  `git fetch origin main && git merge origin/main`. Sin identificadores de modelo en commits/código.

## Diseño (lo que el usuario ya pidió y no hay que romper)

- **Pantalla de acceso (Bienvenida)** conserva el branding de Islas (imagen `login-hero`, logo,
  textos, botón "Continuar", enlace de invitación). No reemplazar por la maqueta 1.
- Celular: solo 10 dígitos y mostrado con formato.
- Lo más nativo posible (HIG): `List` agrupada, SF Symbols, colores del sistema, modo oscuro,
  esquinas continuas, `chevron.forward`, monogramas tipo Contactos, Dynamic Type y VoiceOver.
- Encabezados de lista con `Section { } header: { }` (`ListHeaderSection`) y
  `.listRowInsets(EdgeInsets())`; nunca `Section("título") { } footer:`.
- Confirmaciones con `.alert` (no `confirmationDialog`: en iOS 26 sale como popover al fondo).
- Acciones al deslizar con `.tint(.red)`, **sin** `role: .destructive` cuando el borrado es
  asíncrono (tronaba la `List`).
- Fechas siempre con `Locale.app` (es_MX) y `sentenceCased` en lugar de `capitalized`.
- Íconos de Cuenta con `SettingsIcon` (glifo al 60 % de una caja fija); preferencia de apariencia
  "De colores / Color de acento" (iOS no expone el estilo de íconos del inicio a las apps).
- Pánico: barra tipo mini reproductor de Apple Music (`tabViewBottomAccessory`, se compacta al
  hacer scroll); mantener presionado con rampa háptica (`.holdToConfirm`).
- iPhone Duo: nada de `UIScreen.main`, idiom u orientación para layout; size classes,
  `readableContentWidth`, `AdaptiveColumns` y `TabView .sidebarAdaptable`.

## Estado actual

Hecho con mocks y la capa de red/sesión real: secciones **A** (registro completo, cuenta existente
3a/3b, aprobación, permisos, Face ID, Inicio y estados del botón), **B** (visitas, invitación única y
de evento, recurrentes, detalle, paquetería), **C** (Mi QR TOTP, historial, paquetes), **D** (pánico
en la app: mantener, cuenta regresiva, alerta dentro/fuera) y **F** (cuenta, familia, dispositivos,
contactos, huéspedes, permiso de obra, propietario no residente). Notificaciones locales simuladas con
categorías `VISITA_PENDIENTE` / `VISITA_INFO` desde **Cuenta › Simulación**.

## Pendiente por integrar del brief

Marca cada punto al terminarlo y mueve los supuestos a `DECISIONES.md`.

### Requiere nuevos targets en Xcode (pedir al usuario que los cree)

- [ ] **Keychain Sharing + App Group** en todos los targets y `AppInfo.keychainAccessGroup` con el
      grupo, para compartir la sesión con widgets, extensión e intents (prerrequisito de todo lo de
      abajo).
- [ ] **Notification Service Extension** (fase 1): descarga la foto de la visita y la adjunta;
      muestra el tipo Visita/Servicio. Push `VISITA_PENDIENTE` con `id`, tipo y URL de foto.
- [ ] **Live Activity** (fase 1, pantallas 11–12) con ActivityKit y push: cuenta regresiva de 60 s,
      botones Autorizar/Rechazar en pantalla bloqueada y Dynamic Island (compacta: iniciales a la
      izquierda, tiempo a la derecha). Se cierra en todos los teléfonos de la casa cuando alguien
      responde (RF-06). Al agotarse dice "sin respuesta"; **nunca** se autoriza sola (RF-04).
      Enviar el push token de ActivityKit al backend (contrato pendiente).
- [ ] **Widgets iOS** (fase 2–3, pantalla 30): mediano interactivo (visita pendiente + abrir pluma /
      solicitar paso) y chico de pánico, que con un toque abre la pantalla 24 y **no** envía directo
      (RF-41). Pantalla bloqueada: distancia a la entrada y visitas pendientes (pantalla 31).
- [ ] **Controles del Centro de control** (`ControlWidget`, iOS 18, fase 4): Abrir pluma, Pánico y
      Mi QR; también en las esquinas de la pantalla bloqueada.
- [ ] **App watchOS independiente** (sección G, pantallas 39–43): aviso de visita con Autorizar /
      Rechazar (RF-03), app con abrir pluma (basta reloj puesto y desbloqueado, RF-68), Mi QR,
      complicaciones y Smart Stack (target de widgets de watchOS). Registra su propia llave;
      WatchConnectivity solo para la sesión inicial. La caída (pantalla 42) es **fase 5 y
      propuesta**: requiere permiso de Apple, no presentarla como confirmada.

### En el target actual

- [ ] **App Intents / Siri** (fase 4, pantallas 28–29, RF-30 a RF-34): `AutorizarVisitaIntent`
      (si hay varias pendientes pregunta cuál; visitas como `AppEntity`), `AbrirPlumaIntent` (mismas
      reglas de geocerca y carril: en compartido "Solicitar paso"; fuera de la geocerca responde que
      hay que estar cerca), `PanicoIntent`. `AppShortcutsProvider` con frases que usan
      `AppInfo.name`. Exigir dispositivo desbloqueado (RF-32). Asignables al botón de Acción (RF-34).
      Los intents deben llamar a los mismos repositorios que la app.
- [ ] **Registro de APNs/FCM**: pedir el device token, enviarlo al backend y manejar el push real
      (hoy solo hay avisos locales simulados). Decisión abierta: APNs directo o FCM.
- [ ] **App Attest** (`DCAppAttestService`) al registrar la llave pública del dispositivo
      (`attestation` va `nil` hoy).
- [ ] **Ubicación en segundo plano durante el pánico**: `CLBackgroundActivitySession` + Background
      Modes (ubicación) para seguir mandando la ubicación con la app cerrada (ver
      `PanicViewModel`). Usar `CLMonitor` para las geocercas (entrada 150 m y perímetro).
- [ ] **Persistencia con SwiftData**: caché de visitas, recurrentes, invitaciones e historial para
      abrir sin red.
- [ ] **Escalamiento visible (RF-04)**: en la visita pendiente mostrar que a los 60 s se escala a
      WhatsApp y llamada y que queda "sin respuesta".
- [ ] **Avisos a los demás integrantes (RF-06)**: cuando otro responde, mostrar quién (ya llega el
      409 `ALREADY_RESPONDED`; falta reflejarlo en la Live Activity y en el aviso).
- [ ] **Servicio con varias viviendas (RF-71)** y **lista restringida** como aviso/estado
      ("posible coincidencia", RF-86) en la visita.
- [ ] **Huésped temporal** con su propio QR durante la estancia y aviso por entrada (RF-92); **permiso
      de obra** con resumen diario y aviso fuera de horario (RF-89) — hoy son formularios con mock.
- [ ] **Arrendatario con fin de contrato (RF-84)**: pedir confirmación o baja al llegar la fecha.
- [ ] **Crashlytics o Sentry** (única dependencia externa permitida además de
      `swift-openapi-generator`, que se integra cuando exista el OpenAPI).

### Calidad (criterio de entrega por fase)

- [ ] Target de pruebas con **Swift Testing**: `AuthInterceptor` (refresh proactivo, 401 → un
      reintento, single-flight), `RequestSigner`, `ResidentQRGenerator` (TOTP), `SessionStore`
      (transiciones), reglas de geocerca/carril y `MockServer`.
- [ ] **XCUITest** de registro, autorizar visita y abrir pluma (el brief lo exige).
- [ ] **SwiftLint y SwiftFormat** sin warnings.
- [ ] Revisión de accesibilidad: VoiceOver y texto grande en todas las pantallas (RNF-10).
- [ ] Preparar localización (String Catalog) aunque el lanzamiento sea solo es-MX (RNF-09).

### Estructura (opcional, mecánico)

- [ ] Mover carpetas a paquetes SPM: `Core` → `AccessCore`, `DesignSystem` → `AccessUI`,
      `Features/X` → `FeatureX` (necesario para compartir código con widgets, intents y watchOS).
- [ ] iPhone Duo con Xcode 27.1: `GeometryProxy.reservedRegions(kind: .division)` y
      `onHingeChange` para colocar las columnas según el pliegue real.

## Decisiones abiertas (preguntar, no decidir)

- Si el Apple Watch cuenta dentro de los 3 dispositivos (en la maqueta sí).
- iOS 17 o iOS 18 como mínimo (los controles requieren iOS 18).
- Push por APNs directo o FCM.
- Nombre definitivo de la app (va en las frases de Siri; hoy `AppInfo.name = "Acceso"` y el
  `CFBundleDisplayName` es "Islas Security").
- `.biometryCurrentSet` vs `.userPresence`/`.biometryAny` para la llave del dispositivo.
- Qué puede hacer un menor (en la maqueta, solo su QR).
- Valores finales: tiempo de escalamiento, usos del PIN, límite de aperturas, hora de cierre de
  accesos, retención de datos.
- Verificar con Apple: botón de Acción del Watch Ultra, App Attest en watchOS, App Review de
  ubicación "Siempre" y Critical Alerts, permiso de detección de caídas.

## Fuera de alcance

Backend, app del guardia (tablet Android), Android, Wear OS, panel web, firmware del controlador,
Kotlin Multiplatform, detección de caídas real (sin permiso de Apple) y login con usuario/contraseña.
