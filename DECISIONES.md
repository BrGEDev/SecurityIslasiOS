# DECISIONES.md

Supuestos y decisiones tomadas al construir la app de residentes. Cada punto marcado
**(supuesto)** debe acordarse con backend o con Brandon antes de producción.

## Arquitectura

| Capa | Carpeta | Qué contiene |
|---|---|---|
| App iPhone | `SecurityIslas/app` | Entrada (`IslasSecurityApp`), `AppContainer` (inyección de dependencias), `RootView` (raíz según sesión), `PhoneWatchBridge` (vínculo con el reloj) |
| App reloj | `SecurityIslasWatch Watch App` | `WatchContainer`, `WatchLinkReceiver`, pantallas del reloj y `QRCodeMatrix` |
| Compartido | `Shared` | Lo que compilan los dos targets: `AppInfo`, `Formatting`, `Presentation` (chips y textos de visita), `ViewModels` (`GateViewModel`, `PanicViewModel`), `WatchLink` y `Core` |
| Core · Red | `Shared/Core/Networking` | `Endpoint`, `APIClient` (actor), `HTTPTransport`, `RequestInterceptor`, `AuthInterceptor`, `APIError` |
| Core · Sesión | `Shared/Core/Session` | `SessionStore` (máquina de estados), `TokenStore` (Keychain), `SessionEventBus` |
| Core · Seguridad | `Shared/Core/Security` | `KeychainStore`, `DeviceKeyManager` (Secure Enclave P-256), `BiometricAuthenticator`, `RequestSigner` |
| Core · Modelos/API | `Shared/Core/Models`, `Shared/Core/API` | Modelos de dominio y catálogo de endpoints |
| Core · Repositorios | `Shared/Core/Repositories` | Un protocolo por contrato + implementación remota |
| Core · Mock | `Shared/Core/Mock` | `MockServer` (backend de prueba) y `MockSeed` (datos de las maquetas) |
| Core · Servicios | `Shared/Core/Services` | Ubicación/geocercas, notificaciones, Mi QR (TOTP) |
| Sistema de diseño | `SecurityIslas/DesignSystem` | Botones, campos, avatares, encabezados (solo iPhone) |
| Features | `SecurityIslas/Features/*` | Registro, Inicio, Visitas, Pluma, Historial, Pánico, Cuenta |
| Siri | `SecurityIslas/Intents` | App Intents y `AppShortcutsProvider` |
| Live Activity (app) | `SecurityIslas/LiveActivity` | `VisitActivityController` |
| Widgets | `IslasWidgets` (+ `Shared`) | Widgets, Live Activity (UI) y controles |
| Notificaciones | `NotificationService` | Foto y tipo en el aviso |
| Reloj | `IslasWatchWidgets` | Complicaciones y Smart Stack |
| Pruebas | `SecurityIslasTests`, `SecurityIslasUITests` | Swift Testing y XCUITest |

- **Carpeta `Shared`.** Es una carpeta sincronizada que pertenece a los dos targets (iPhone y
  reloj): todo archivo nuevo ahí se compila en ambos. Lo exclusivo de una plataforma va detrás de
  `#if os(iOS)` / `#if os(watchOS)` (CoreImage, Face ID). No se usan excepciones de membresía.
- **Carpetas en lugar de paquetes SPM.** El brief pide paquetes `AccessCore`, `AccessUI`, `Feature*`.
  Se dejó la misma separación por carpetas dentro del target porque crear paquetes y targets
  nuevos requiere editar el proyecto en Xcode. Mover cada carpeta a su paquete es mecánico:
  `Shared/Core` → `AccessCore`, `DesignSystem` → `AccessUI`, `Features/X` → `FeatureX`.
- **Concurrencia.** El target usa Swift 6 con aislamiento `MainActor` por defecto. Todo lo que
  corre fuera del hilo principal está marcado explícitamente: modelos y DTOs `nonisolated`,
  `APIClient`, `AuthInterceptor`, `KeychainTokenStore` y `MockServer` son `actor`.
- **Un solo camino de red.** Las vistas → ViewModels → repositorios → `APIClient` → interceptores
  → transporte. Con el backend mock, el transporte es `MockTransport`; con el real,
  `URLSessionTransport`. Repositorios, interceptores y vistas no cambian.
- `swift-openapi-generator` queda pendiente hasta tener el OpenAPI: el cliente generado puede usar
  el mismo transporte y los mismos interceptores.

## Red y sesión

- **Interceptor de token (`AuthInterceptor`).**
  1. Agrega `Authorization: Bearer` a toda petición con `requiresAuth`.
  2. Si el access token vence en menos de 30 s, lo renueva *antes* de enviar.
  3. Ante un 401, renueva y el `APIClient` reintenta **una** vez.
  4. Renovaciones simultáneas se agrupan en una sola llamada (single-flight).
  5. Si otra petición ya renovó el token mientras esta viajaba, solo reintenta.
  6. Si el refresh token es rechazado, borra la sesión y emite `.expired`; `SessionStore` regresa a
     Bienvenida con el aviso "Tu sesión expiró".
  7. El refresh usa un `APIClient` sin interceptor de token para evitar recursión.
- **(supuesto)** El refresh token rota en cada renovación.
- **(supuesto)** Errores de negocio con cuerpo `{ "code": "...", "message": "..." }`. Códigos usados:
  `INVALID_OTP`, `DEVICE_LIMIT`, `PENDING_APPROVAL`, `OUTSIDE_GEOFENCE`, `TOO_SOON`, `CONTROLLER_OFFLINE`,
  `ALREADY_RESPONDED`, `RENTED_HOME`, `HOLDER_ONLY`, `SIGNATURE_REQUIRED`, `INVALID_SIGNATURE`,
  `REPLAYED_REQUEST`, `DEVICE_REVOKED`, `INVALID_REFRESH_TOKEN`.
- **(supuesto)** Las fechas viajan en ISO 8601 sin fracciones de segundo.
- Encabezados comunes: `X-Device-Id` (UUID estable guardado en Keychain), `X-Client: ios/<versión>`,
  `Accept-Language: es-MX`.
- Al volver a abrir la app no se pide login: entra con el perfil guardado en Keychain y lo
  actualiza en segundo plano con `GET me`.

## Firma de acciones sensibles (RF-67, RNF-05)

- **Decidido (Brandon): `.biometryCurrentSet`.** La llave P-256 del Secure Enclave se crea con
  `[.privateKeyUsage, .biometryCurrentSet]`: si se agregan o quitan caras/huellas, la llave deja de
  servir. La app lo detecta antes de firmar (compara el estado del dominio biométrico guardado al
  crearla), borra la llave y pide de nuevo Face ID con un aviso; se registra una llave nueva
  (`POST devices/key`). La biometría nunca es un booleano local: es lo que permite firmar.
- "Usar el código del iPhone" (pantalla 8) o un iPhone sin biometría registrada crea la llave con
  `[.privateKeyUsage, .devicePasscode]` **(supuesto)**: respaldo de RF-67.
- Con llave biométrica se evalúa `.deviceOwnerAuthenticationWithBiometrics` (sin botón de código),
  porque un contexto autenticado con código no le sirve a una llave `.biometryCurrentSet`.
- **(supuesto)** Mensaje firmado: `MÉTODO \n ruta \n timestamp \n nonce \n sha256(body)`, ECDSA
  P-256/SHA-256 en DER, enviado en `X-Signature`, `X-Signature-Timestamp`, `X-Signature-Nonce`.
  Vigencia 120 s y nonce de un solo uso.
- Se reutiliza la autenticación 10 s para no pedir Face ID dos veces seguidas.
- Requieren firma: abrir pluma / solicitar paso, crear y revocar recurrentes, política de paquetería,
  invitar/quitar familia, agregar/quitar contactos, quitar dispositivos y cerrar la alerta de pánico.
- No requieren firma: autorizar/rechazar visitas (RF-02), invitaciones únicas (RF-07), huéspedes.
- En la pantalla 3b el iPhone nuevo aún no tiene llave: la baja del dispositivo viejo va solo con el
  token recién emitido por el SMS. **(supuesto)** Backend debe aceptarlo solo en ese momento.
- **Simulador:** no hay Secure Enclave; se usa una llave de software para poder desarrollar. En un
  iPhone real siempre es Secure Enclave.
- **App Attest (supuesto de contrato).** `POST devices/attest-challenge` → `{ challenge, expiresAt }`;
  la app genera una llave de App Attest y la atesta con
  `clientDataHash = SHA256(reto ‖ llave pública del dispositivo)`, así la atestación queda ligada a
  la llave del Secure Enclave. `POST devices/key` lleva `attestation`, `attestationKeyId` y
  `attestationChallenge`. Sin soporte (simulador) se registra sin atestación y el backend decide.
  En watchOS no se usa hasta confirmar con Apple.
- **Pruebas de UI en el simulador** (`-uiTesting YES`): se omite Face ID y se reinicia el backend de
  prueba y la sesión. Solo existe en el simulador.

## Pluma y Mi QR

- El botón valida la geocerca en el teléfono y el backend la vuelve a validar. Carril exclusivo →
  "Abrir pluma"; compartido → "Solicitar paso"; fuera → "Lejos de la entrada".
- **(supuesto)** `GET home` regresa los carriles con su tipo y coordenadas, el radio de la entrada
  (150 m) y el perímetro del fraccionamiento.
- "Pluma abierta" solo se muestra cuando el backend confirma el pulso (`outcome: opened`).
- **(supuesto)** Mi QR: HMAC-SHA256 tipo TOTP, periodo 30 s, 8 dígitos, payload `ACC1.<userId>.<código>`.
  El secreto llega por `GET qr-seed` y se guarda en Keychain para funcionar sin internet.

## Pánico

- Mantener 3 s → cuenta regresiva de 5 s cancelable → alerta.
- **Decidido (Brandon):** widget, control, botón de Acción, Siri y complicación del reloj **no**
  piden mantener presionado: un toque inicia directo la cuenta regresiva cancelable (RF-41, que
  prevalece sobre la nota de la maqueta 24). En una emergencia no debe haber pasos de más. La
  pantalla de mantener presionado queda para VoiceOver y el botón de pánico dentro de la app del
  reloj.
- La cuenta regresiva arranca de inmediato; la ubicación se obtiene mientras corre.
- **(supuesto)** El backend decide el destino con la ubicación enviada (guardias dentro del perímetro,
  contactos fuera); la app lo anticipa con la misma geocerca.
- **(supuesto)** Estado cada 3 s y ubicación cada 10 s mientras la alerta siga abierta.
- La ubicación del pánico sale de `LocationService.trackCoordinates()`, que abre una
  `CLBackgroundActivitySession` (modo de fondo `location` activado): sigue enviándose con la app en
  segundo plano. El estado se consulta cada 3 s y la ubicación se manda cada 10 s **(supuesto)**.
- Geocercas con `CLMonitor` (iOS): una por carril (radio de la entrada) y el perímetro. Se registran
  al cargar Inicio; el pánico usa el último estado si no hay posición precisa. watchOS no tiene
  `CLMonitor`: se calcula con la última posición.

## Notificaciones

- Categorías registradas: `VISITA_PENDIENTE` (Rechazar funciona bloqueado; Autorizar con
  `.authenticationRequired`) y `VISITA_INFO` (sin botones). Las acciones llaman al mismo repositorio.
- **Decidido: APNs directo.** La app registra el token en cada arranque y lo sube con
  `PUT devices/current/push-token` `{ kind: alert | liveActivityStart, token (hex), environment, topic }`
  **(supuesto)** cuando hay sesión; solo lo vuelve a subir si cambia el token o la cuenta.
- **Contenido del push (supuesto):**
  - Visita: `aps.category = VISITA_PENDIENTE`, `mutable-content: 1`, `interruption-level:
    time-sensitive`; raíz `type: visit.pending`, `visitId`, `kind`, `photoURL` (https firmada y de
    corta vida, sin token) y `residence`.
  - Informativo: `aps.category = VISITA_INFO`, `type: visit.info`.
  - Otro integrante respondió (RF-06): silencioso (`content-available: 1`) con `type: visit.responded`,
    `visitId`, `visitName`, `decision`, `respondedBy`. La app quita el aviso, cierra la Live Activity
    y avisa quién respondió.
- **Notification Service Extension:** descarga la foto y la adjunta; si no trae título/subtítulo,
  pone "Visita/Servicio en caseta". Sin foto a tiempo, el aviso sale solo con texto.
- Tocar el aviso abre Visitas › Hoy.

## Live Activity (pantallas 11 y 12)

- Una actividad por visita pendiente. La app la inicia al cargar Inicio (y la cierra si la visita ya
  no está pendiente); con la app cerrada la inicia el backend con el token *push to start*
  (iOS 17.2+, `kind: liveActivityStart`).
- Cada actividad manda su token a `PUT visits/{id}/activity-token` `{ token, environment }`
  **(supuesto)** para que el backend la actualice o la cierre en todos los teléfonos de la casa.
- Cuenta regresiva hasta `respondBy` (si el backend no lo manda, llegada + 60 s). Al vencer queda
  "obsoleta" y dice que se está escalando; al cerrarse sin respuesta dice "Sin respuesta · no entró".
  Nunca se autoriza sola (RF-04).
- Botones: Rechazar (`VisitDecisionIntent`, funciona bloqueado) y Autorizar
  (`AuthorizeVisitFromLockScreenIntent`, `.requiresAuthentication`, RF-02). Son `LiveActivityIntent`:
  corren en el proceso de la app y llaman al mismo repositorio.

## Widgets y controles

- Los widgets no hacen red ni leen la sesión: la app escribe `WidgetSnapshot` en el App Group
  `group.app.security.islasgower` al cargar Inicio y recarga los widgets. Por eso **no** se activó
  Keychain Sharing (`AppInfo.keychainAccessGroup` sigue en `nil`). Al cerrar sesión se borra.
- Mediano: visita en caseta con Rechazar / Autorizar (mismos intents) y botón de abrir pluma o
  solicitar paso. Chico: pánico. Pantalla bloqueada: distancia a la entrada y visitas pendientes.
- Abrir pluma, pánico y Mi QR abren la app con `islassecurity://gate|panic|qr`: abrir usa el mismo
  botón de Inicio (geocerca, carril y Face ID) y el pánico inicia la cuenta regresiva cancelable
  (RF-41). Controles del Centro de control (iOS 18) con `OpenAppTargetIntent` (`OpenIntent` en
  `Shared`, miembro de la app y de la extensión, como pide Apple; corre en la app y atiende el mismo
  `AppLink`). Con `OpenURLIntent` y el esquema propio los botones no hacían nada.
- Complicaciones del reloj: `islassecurity://gate|panic|qr` abren la página correspondiente.

## Siri (RF-30 a RF-34)

- `AutorizarVisitaIntent` (visitas pendientes como `VisitEntity`; si hay varias pregunta cuál),
  `AbrirPlumaIntent` (mismas reglas de geocerca y carril; abre la app porque firma con Face ID),
  `PanicoIntent` (inicia la cuenta regresiva cancelable) y `MiQRIntent`. Todos exigen el iPhone
  desbloqueado (`.requiresAuthentication`). Frases con el nombre de la app.
- Los intents usan `AppContainer.shared` (una instancia por proceso) y esperan el arranque de la
  sesión (`SessionStore.activeProfile()`).

## Caché sin red (SwiftData)

- `OfflineCache` guarda la respuesta JSON del backend por clave (Inicio, visitas de hoy,
  invitaciones, recurrentes, paquetes, historial). Solo se usa si falla la red; las acciones nunca
  salen de la caché. Inicio muestra "Sin conexión · datos de …". Se borra al cerrar sesión.

## Roles

- **Decidido (Brandon): el menor** solo abre la pluma o solicita paso para su propio paso y usa su
  QR. No ve Visitas, no autoriza, no invita ni cambia recurrentes, paquetería, familia o contactos.
  El backend responde 403 `MINOR_NOT_ALLOWED` **(supuesto)**. Mantiene el pánico (seguridad).
- El propietario no residente nunca usa el botón de abrir (RF-87), esté o no rentada la casa.

## Visitas (RF-04, RF-06, RF-71, RF-86)

- `respondBy` **(supuesto)**: hasta cuándo puede responder antes de escalar; la tarjeta explica que
  se escala a WhatsApp y llamada y que, sin respuesta, no entra.
- `destinationCount > 1`: servicio a varias viviendas; cada una responde por la suya.
- `restrictedMatch` **(supuesto)**: `possible` (solo el nombre, "posible coincidencia") o
  `confirmed` (placa o identificación: la administración decide; Autorizar se desactiva y el backend
  responde 409 `RESTRICTED_MATCH`).

## Casos de vivienda

- **Huésped (RF-92):** `TemporaryGuest` trae `shareURL`, `pin` y `entries` **(supuesto)**; detalle con
  su QR, reenviar acceso y entradas. El acceso vence solo.
- **Obra (RF-88/89):** `WorkPermit.todayEntries` con `outsideSchedule` y `restrictedMatch`
  **(supuesto)**. El resumen diario se puede apagar; el aviso inmediato fuera de horario o por lista
  restringida siempre llega (lo manda el backend).
- **Fin de contrato (RF-84):** `UserProfile.contractEndsOn` **(supuesto)**. A 7 días o menos
  **(supuesto)**, Inicio pregunta "¿Sigues viviendo aquí?": `POST residence/tenancy`
  `{ decision: stay | leave }`, firmado. "Me mudo" da de baja el acceso en todos los dispositivos y
  cierra la sesión.

## Backend de prueba (MockServer)

`MockServer` atiende las mismas `URLRequest` que atendería el backend: valida tokens, los emite con
vencimiento corto (2 min, configurable a 20 s) para ejercitar el refresh, verifica las firmas con la
llave pública registrada, valida geocerca, tipo de carril y el tiempo mínimo entre pulsos (5 s, RF-80).
Cuentas y llaves se guardan en `UserDefaults`; visitas, paquetes, etc. se reinician en cada arranque.

| Número | Caso |
|---|---|
| 222 123 4567 · 221 848 6093 | Brandon, cuenta existente (3a), con un Apple Watch vinculado |
| 222 999 9999 | Cuenta existente con 3 dispositivos (3b) + un Apple Watch, que no cuenta |
| 222 555 0000 | Precargado por la administración (RF-63) → pantalla 5 → aprobado |
| 551 234 5678 | Laura, propietaria no residente con casa rentada (pantalla 38) |
| 222 777 0000 | Diego, menor: su QR y la pluma para su paso |
| 222 888 0000 | Sofía, arrendataria con el contrato por terminar (RF-84) |
| Cualquier otro | Residente nuevo → 4 → 5 → 6; se aprueba solo a los ~12 s |

Código SMS: **123456**. Enlace de invitación: cualquier código de 4+ caracteres (ej. `7KX2`);
`0000` es inválido.

**Cuenta › Simulación** (solo con mock): posición simulada (carril de residentes, carril compartido,
lejos), llegada de visita/servicio con notificación local, "otro integrante responde primero"
(RF-06), vida del access token y reinicio de datos. Las cuentas de prueba nuevas se agregan solas
aunque ya haya un estado guardado.

Para usar el backend real: lanzar con el argumento `-useLiveAPI YES` y ajustar `APIConfig.staging`.

## Diseño nativo e iPhone Duo

- **Acciones:** `ActionButtonStyle` (cápsula, 50 pt que escalan con Dynamic Type, Liquid Glass en
  iOS 26 y grises del sistema al deshabilitarse). La pantalla de acceso conserva `IslasButton` (marca).
- **Barras inferiores:** en iOS 26 los botones flotan sobre el contenido; antes usan el material `.bar`.
- **Inicio:** título grande nativo ("Hola, Brandon") con la vivienda como `navigationSubtitle` en
  iOS 26 (en iOS 17–25, debajo del título); avatar en la barra; carga con `.redacted`.
- **Cuenta:** filas con íconos de color al estilo de Ajustes y `LabeledContent`.
- **Listas:** acciones al deslizar con íconos (autorizar a la izquierda, rechazar a la derecha) y
  menús contextuales con las mismas acciones; háptico de selección en el segmentado.
- **Detalles:** esquinas continuas, `chevron.forward`, monogramas tipo Contactos, chips en cápsula,
  símbolos jerárquicos y efectos de símbolo solo en cambios de estado (sin animaciones perpetuas).
- **iPhone Duo** (guía de Apple "Prepare your app for iPhone Duo"):
  - Sin `UIScreen.main`, idiom ni orientación para decidir layout; todo se mide contra el contenedor.
    Mi QR obtiene la pantalla desde la `UIWindowScene`.
  - La pantalla interior es regular × regular: `TabView` con `.sidebarAdaptable` (iOS 18+),
    `readableContentWidth()` limita el ancho de listas y formularios, e Inicio pasa a dos columnas
    (`AdaptiveColumns`) con un hueco central para que nada quede sobre el pliegue.
  - Fondos con `ignoresSafeArea()` y controles dentro del área segura (que puede ser asimétrica).
  - **Pendiente (Xcode 27.1):** usar `GeometryProxy.reservedRegions(kind: .division)` para colocar
    las columnas según el pliegue real y `onHingeChange` si hace falta. No se usaron todavía porque
    requieren iOS 27.1 / Xcode 27.1 y el proyecto debe compilar con 27.0.

## Apple Watch (sección G)

- **App independiente** (`WKRunsIndependentlyOfCompanionApp`), watchOS 10+. Comparte la carpeta
  `Shared` con el iPhone: misma red, interceptor de token, sesión, firma, mocks y ViewModels de
  pluma y pánico.
- **Vínculo (supuesto, acordar con backend).** WatchConnectivity solo para la sesión inicial:
  1. iPhone › Cuenta › Dispositivos › "Vincular Apple Watch" → `POST devices/watch-link` firmado
     (agregar un dispositivo es un cambio de cuenta, RF-67) → código de un solo uso (5 min).
  2. El iPhone pasa el código al reloj (`WatchEnvelope.link`).
  3. El reloj crea **su propia llave** y la canjea: `POST auth/watch-link`
     `{ code, device, publicKey, attestation, hardwareBacked }` → tokens + perfil.
  4. Desde ahí el reloj usa su propia sesión (refresh con el mismo `AuthInterceptor`) y funciona
     sin el iPhone cerca.
- **Decidido (Brandon):** los Apple Watch **no cuentan** dentro del límite de 3 dispositivos y se
  pueden vincular varios. El límite (RF-66) es de teléfonos y tabletas (`DeviceModel.countsTowardLimit`).
- **Experiencia de vínculo** (como configurar el reloj en el iPhone): hoja con pasos —
  presentación, instalar la app si falta (abre la app Watch), Face ID, "Vinculando…" con la animación
  `PairingOrb` y un **código de 4 dígitos** que muestran el iPhone y el reloj (derivado del código de
  un solo uso) para confirmar a simple vista que es el mismo reloj, y "Listo".
- **Diseño del reloj:** lenguaje de watchOS 10 — páginas verticales con la Digital Crown (En caseta
  solo si hay visitas, Pluma, Mi QR), fondos con el color de cada estado (`BrandPalette`, los mismos
  degradados de la tarjeta de pluma del iPhone), Cuenta y Pánico en la barra superior, y Autorizar /
  Rechazar como botones de llamada.
- **Sin Face ID en el reloj (RF-68).** La llave del reloj se crea con `[.privateKeyUsage]` y
  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`: solo firma con el reloj desbloqueado, y el
  reloj se bloquea al quitárselo. `BiometricAuthenticator` no pide nada en watchOS.
- **Mi QR en el reloj.** watchOS no tiene CoreImage: `QRCodeMatrix` codifica el QR (modo byte,
  corrección M, versiones 1–10). Validado módulo a módulo contra una librería de referencia
  (segno) en las 8 máscaras.
- **Quitar el reloj** en Dispositivos o cerrar sesión en el iPhone le manda `unlinked` al reloj,
  que cierra su sesión. Con el backend real, además, el token del reloj deja de servir (RF-65).
- **Mock.** Cada app tiene su propio `MockServer`. Al vincular, el iPhone le pasa al reloj su
  cuenta de prueba; las visitas simuladas en el iPhone también se mandan al reloj, y el reloj tiene
  su propio menú "Simulación". Las respuestas no se sincronizan entre los dos servidores de prueba
  (con el backend real sí).
- Complicaciones y Smart Stack: target `IslasWatchWidgetsExtension` (pluma, pánico, Mi QR).
- **Pendiente:** escena de notificación personalizada con la foto, Siri en el reloj y caída (fase 5,
  requiere permiso).

## Otras decisiones

- La pantalla de Bienvenida conserva el diseño de marca de Islas (imagen `login-hero`, logo, textos y
  botón "Continuar"). Prevalece sobre la maqueta 1 del brief por ser branding de la empresa.

- Lada México corregida a **+52** (estaba en 51).
- Se agregaron al Info.plist generado: `NSFaceIDUsageDescription`, `NSLocationWhenInUseUsageDescription`
  y `NSLocationAlwaysAndWhenInUseUsageDescription` (sin ellas la app se cierra al pedir Face ID).
- **Decidido:** nombre "Islas Security" por ahora (`AppInfo.name` = `CFBundleDisplayName`).
- **Decidido:** mínimo iOS 17; lo de iOS 18 (controles) va detrás de `#available`.

## Pendiente

- Escena de notificación del reloj con foto, Siri y push propios del reloj.
- Universal Links (`associated-domains`) con el dominio real.
- SwiftLint / SwiftFormat, revisión de accesibilidad y String Catalog.
- Crashlytics o Sentry.
