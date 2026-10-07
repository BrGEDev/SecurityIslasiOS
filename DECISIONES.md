# DECISIONES.md

Supuestos y decisiones tomadas al construir la app de residentes. Cada punto marcado
**(supuesto)** debe acordarse con backend o con Brandon antes de producción.

## Arquitectura

| Capa | Carpeta | Qué contiene |
|---|---|---|
| App | `SecurityIslas/App` | Entrada (`IslasSecurityApp`), `AppContainer` (inyección de dependencias), `RootView` (raíz según sesión), `AppInfo` (nombre provisional "Acceso") |
| Core · Red | `Core/Networking` | `Endpoint`, `APIClient` (actor), `HTTPTransport`, `RequestInterceptor`, `AuthInterceptor`, `APIError` |
| Core · Sesión | `Core/Session` | `SessionStore` (máquina de estados), `TokenStore` (Keychain), `SessionEventBus` |
| Core · Seguridad | `Core/Security` | `KeychainStore`, `DeviceKeyManager` (Secure Enclave P-256), `BiometricAuthenticator`, `RequestSigner` |
| Core · Modelos/API | `Core/Models`, `Core/API` | Modelos de dominio y catálogo de endpoints |
| Core · Repositorios | `Core/Repositories` | Un protocolo por contrato + implementación remota |
| Core · Mock | `Core/Mock` | `MockServer` (backend de prueba) y `MockSeed` (datos de las maquetas) |
| Core · Servicios | `Core/Services` | Ubicación/geocercas, notificaciones, Mi QR (TOTP) |
| Sistema de diseño | `DesignSystem` | Botones, campos, chips Visita/Servicio, avatares, encabezados |
| Features | `Features/*` | Registro, Inicio, Visitas, Pluma, Historial, Pánico, Cuenta |

- **Carpetas en lugar de paquetes SPM.** El brief pide paquetes `AccessCore`, `AccessUI`, `Feature*`.
  Se dejó la misma separación por carpetas dentro del target porque crear paquetes y targets
  nuevos requiere editar el proyecto en Xcode. Mover cada carpeta a su paquete es mecánico:
  `Core` → `AccessCore`, `DesignSystem` → `AccessUI`, `Features/X` → `FeatureX`.
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

- La llave P-256 se crea en el Secure Enclave con `SecAccessControl` `[.privateKeyUsage, .userPresence]`
  (biometría **o** código del iPhone). La biometría nunca es un booleano local: es lo que permite firmar.
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
- **Pendiente:** App Attest (`DCAppAttestService`) en el registro de la llave (`attestation` va `nil`).
- **Pendiente de decidir (sección 9):** `.userPresence` no invalida la llave si cambian las caras o
  huellas. Si se decide `.biometryCurrentSet`, basta cambiar la bandera en `DeviceKeyManager`.

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
- **(supuesto)** El backend decide el destino con la ubicación enviada (guardias dentro del perímetro,
  contactos fuera); la app lo anticipa con la misma geocerca.
- **(supuesto)** Estado cada 3 s y ubicación cada 10 s mientras la alerta siga abierta.
- **Pendiente:** `CLBackgroundActivitySession` y modo de fondo de ubicación para seguir enviando la
  ubicación con la app cerrada (requiere activar Background Modes en el target).

## Notificaciones

- Categorías registradas: `VISITA_PENDIENTE` (Rechazar funciona bloqueado; Autorizar con
  `.authenticationRequired`) y `VISITA_INFO` (sin botones). Las acciones llaman al mismo repositorio.
- **Pendiente:** Notification Service Extension (foto), Live Activity y registro del token APNs/FCM
  (sección 9: APNs directo o FCM).

## Backend de prueba (MockServer)

`MockServer` atiende las mismas `URLRequest` que atendería el backend: valida tokens, los emite con
vencimiento corto (2 min, configurable a 20 s) para ejercitar el refresh, verifica las firmas con la
llave pública registrada, valida geocerca, tipo de carril y el tiempo mínimo entre pulsos (5 s, RF-80).
Cuentas y llaves se guardan en `UserDefaults`; visitas, paquetes, etc. se reinician en cada arranque.

| Número | Caso |
|---|---|
| 222 123 4567 · 221 848 6093 | Brandon, cuenta existente (3a), 1 dispositivo |
| 222 999 9999 | Cuenta existente con 3 dispositivos (3b) |
| 222 555 0000 | Precargado por la administración (RF-63) → pantalla 5 → aprobado |
| 551 234 5678 | Laura, propietaria no residente con casa rentada (pantalla 38) |
| Cualquier otro | Residente nuevo → 4 → 5 → 6; se aprueba solo a los ~12 s |

Código SMS: **123456**. Enlace de invitación: cualquier código de 4+ caracteres (ej. `7KX2`);
`0000` es inválido.

**Cuenta › Simulación** (solo con mock): posición simulada (carril de residentes, carril compartido,
lejos), llegada de visita/servicio con notificación local, vida del access token y reinicio de datos.

Para usar el backend real: lanzar con el argumento `-useLiveAPI YES` y ajustar `APIConfig.staging`.

## Otras decisiones

- La pantalla de Bienvenida conserva el diseño de marca de Islas (imagen `login-hero`, logo, textos y
  botón "Continuar"). Prevalece sobre la maqueta 1 del brief por ser branding de la empresa.

- Lada México corregida a **+52** (estaba en 51).
- Se agregaron al Info.plist generado: `NSFaceIDUsageDescription`, `NSLocationWhenInUseUsageDescription`
  y `NSLocationAlwaysAndWhenInUseUsageDescription` (sin ellas la app se cierra al pedir Face ID).
- El `CFBundleDisplayName` sigue siendo "Islas Security" mientras en la UI se usa `AppInfo.name`
  ("Acceso", provisional). Hay que alinearlos cuando se decida el nombre.
- `AppInfo.keychainAccessGroup` está en `nil`. Al agregar widgets, extensión de notificaciones o
  intents, activar Keychain Sharing y poner el grupo para compartir la sesión.
- Un menor (rol `minor`) no autoriza visitas; el backend responde 403 (por decidir, sección F-33).

## Pendiente (fuera de este cambio)

- Targets de widgets/controles/Live Activity, Notification Service Extension, App Intents (Siri) y
  la app de watchOS (secciones E y G).
- Pruebas unitarias (Swift Testing) y de UI (XCUITest) para registro, autorizar visita y abrir pluma.
- SwiftLint / SwiftFormat.
