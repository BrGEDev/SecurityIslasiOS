# CLAUDE.md

Instrucciones para Claude al trabajar en este repo: app de residentes (iPhone y Apple Watch) de
una plataforma mexicana de acceso y seguridad para fraccionamientos. La fuente es el **brief del
agente iOS (requerimientos 0.4, 45 pantallas)**; aquí está lo esencial y, sobre todo, **lo que falta
por integrar**. Los supuestos tomados están en `DECISIONES.md`: léelo antes de cambiar red, sesión,
firma o mocks, y anota ahí cada supuesto nuevo.

## Reglas de trabajo

- **Prioridad de fuentes:** reglas de negocio > requerimientos (RF/RNF) > maquetas > stack.
  Si algo no está definido (ver "Decisiones abiertas"), pregunta en lugar de decidir.
- **Backend no existe todavía.** Todo va contra `MockServer` (`Shared/Core/Mock`) a través de la misma
  capa de red que usará el backend real. No inventes endpoints definitivos: agrega el endpoint en
  `Shared/Core/API/API.swift`, su protocolo en `Shared/Core/Repositories`, la ruta en `MockServer` y
  marca los campos supuestos en `DECISIONES.md`.
- **Dos targets, una carpeta compartida.** `SecurityIslas/` es solo iPhone, `SecurityIslasWatch Watch
  App/` es solo reloj y `Shared/` se compila en los dos (red, sesión, firma, modelos, mocks,
  ViewModels de pluma y pánico, chips de visita). Todo lo que pongas en `Shared/` debe compilar en
  watchOS: nada de UIKit/CoreImage/Face ID sin `#if os(iOS)`.
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
  solos. Targets, capabilities y extensiones nuevas se crean con las herramientas de Xcode (o se le
  piden al usuario si no están disponibles).
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

Hecho con mocks y la capa de red/sesión real: secciones **A** a **G** (sin caída). Además:

| Bloque | Dónde |
|---|---|
| Push por APNs (token, push silencioso RF-06, abrir la visita desde el aviso) | `PushRegistrar`, `AppDelegate`, `AppContainer.handleRemote` |
| App Attest al registrar la llave | `Shared/Core/Security/AppAttester.swift` |
| Llave `.biometryCurrentSet` (o código del iPhone si así se eligió) | `DeviceKeyManager`, `SessionStore.checkDeviceKey` |
| Pánico en segundo plano (`CLBackgroundActivitySession`) y geocercas con `CLMonitor` | `LocationService`, `PanicViewModel` |
| Caché sin red con SwiftData | `Shared/Core/Persistence/OfflineCache.swift`, `CachedVisitsRepository` |
| RF-04, RF-06, RF-71, RF-86 en la visita | `Visit`, `LiveVisitCard`, `VisitPresentation` |
| Huésped con QR (RF-92), entradas de obra (RF-88/89), fin de contrato (RF-84) | `PropertyViews`, `TenancyCard` en `HomeView` |
| Siri / Atajos / botón de Acción | `SecurityIslas/Intents/AccessIntents.swift` |
| Widgets, Live Activity y controles (iOS 18) | target `IslasWidgetsExtension` (carpeta `IslasWidgets` + `Shared`) |
| Foto y tipo en el aviso | target `NotificationService` |
| Complicaciones y Smart Stack del reloj | target `IslasWatchWidgetsExtension` |
| Pruebas | `SecurityIslasTests` (Swift Testing) y `SecurityIslasUITests` (XCUITest, `-uiTesting YES`) |

Targets: `SecurityIslas`, `SecurityIslasWatch Watch App`, `IslasWidgetsExtension`, `NotificationService`,
`IslasWatchWidgetsExtension`, `SecurityIslasTests`, `SecurityIslasUITests` (más las plantillas de
pruebas del reloj). `Shared/` también se compila en `IslasWidgetsExtension`. App Group
`group.app.security.islasgower` en la app y los widgets (foto de estado `WidgetSnapshot`).
Enlaces internos `islassecurity://gate|panic|qr|visits` (`AppLink`).

## Pendiente por integrar del brief

Marca cada punto al terminarlo y mueve los supuestos a `DECISIONES.md`.

- [ ] **Keychain Sharing**: no hizo falta (los widgets leen `WidgetSnapshot` del App Group y los
      botones corren en el proceso de la app). Activarlo solo si una extensión necesita la sesión;
      al hacerlo, migrar los ítems del Keychain (si no, todos tendrán que volver a entrar).
- [ ] **Escena de notificación del reloj con foto** (pantalla 39, `WKUserNotificationHostingController`).
- [ ] **Siri en el reloj** (RF-30/31 en Apple Watch) y push propio del reloj.
- [ ] **Crashlytics o Sentry** (única dependencia externa permitida además de
      `swift-openapi-generator`, que se integra cuando exista el OpenAPI).
- [ ] **Universal Links**: falta el entitlement `associated-domains` con el dominio real de
      invitaciones (`AppInfo.inviteHost` es de ejemplo).
- [ ] Contrato con backend de todo lo marcado **(supuesto)** en `DECISIONES.md`.

### Calidad (criterio de entrega por fase)

- [x] Target de pruebas con **Swift Testing** (interceptor, firma, TOTP, geocerca/carril, roles,
      push, visitas y `MockServer`). Falta: transiciones de `SessionStore`.
- [x] **XCUITest** de registro, autorizar visita y abrir pluma.
- [ ] **SwiftLint y SwiftFormat** sin warnings.
- [ ] Revisión de accesibilidad: VoiceOver y texto grande en todas las pantallas (RNF-10).
- [ ] Preparar localización (String Catalog) aunque el lanzamiento sea solo es-MX (RNF-09).

### Estructura (opcional, mecánico)

- [ ] Mover carpetas a paquetes SPM: `Core` → `AccessCore`, `DesignSystem` → `AccessUI`,
      `Features/X` → `FeatureX`.
- [ ] iPhone Duo con Xcode 27.1: `GeometryProxy.reservedRegions(kind: .division)` y
      `onHingeChange` para colocar las columnas según el pliegue real.

## Decisiones ya tomadas (Brandon)

- Los Apple Watch **no cuentan** en el límite de 3 dispositivos y se pueden tener varios.
- Mínimo **iOS 17** (los controles del Centro de control van detrás de `if #available(iOS 18)`).
- Push por **APNs directo**.
- Nombre: **Islas Security** por ahora (`AppInfo.name` = `CFBundleDisplayName`).
- Llave del dispositivo con **`.biometryCurrentSet`**: si cambian las caras o huellas, se vuelve a
  activar Face ID y se registra una llave nueva.
- **Menor**: solo abre la pluma (o solicita paso) para su propio paso y usa su QR; no autoriza
  visitas, no invita ni cambia accesos.
- **Pánico desde atajos**: widget, control, botón de Acción, Siri y complicación inician directo la
  cuenta regresiva cancelable (sin mantener presionado).
- **Git**: todo lo trabajado se sube a `main` al terminar cada cambio.

## Decisiones abiertas (preguntar, no decidir)

- Valores finales: tiempo de escalamiento, usos del PIN, límite de aperturas, hora de cierre de
  accesos, retención de datos, anticipación del aviso de fin de contrato.
- Nombre definitivo de la app (las frases de Siri usan el nombre de la app).
- Verificar con Apple: botón de Acción del Watch Ultra, App Attest en watchOS, App Review de
  ubicación "Siempre" y Critical Alerts, permiso de detección de caídas.

## Fuera de alcance

Backend, app del guardia (tablet Android), Android, Wear OS, panel web, firmware del controlador,
Kotlin Multiplatform, detección de caídas real (sin permiso de Apple) y login con usuario/contraseña.
