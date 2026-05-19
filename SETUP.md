# LocalPlayer — Guía de instalación en iPhone

Reproductor de música local con diseño estilo Apple Music. Lee canciones desde la app Archivos y las reproduce automáticamente de forma continua.

---

## Requisitos

| Elemento | Versión necesaria |
|---|---|
| Mac | macOS 14 Sonoma o superior |
| Xcode | 16.0 o superior |
| iPhone | iOS 18.0 o superior |
| Apple ID | Cualquiera (cuenta gratuita sirve) |

> **No necesitas pagar los $99/año de Apple Developer para instalarlo en TU propio iPhone.**

---

## Paso 1 — Instalar Xcode

1. Abre la **Mac App Store** en tu Mac.
2. Busca **Xcode** e instálalo (pesa ~8 GB, tarda tiempo).
3. Abre Xcode una vez y acepta las licencias.

---

## Paso 2 — Crear el proyecto en Xcode

1. Abre **Xcode → File → New → Project…**
2. Elige **iOS → App** y haz clic en **Next**.
3. Rellena así:
   - **Product Name:** `LocalPlayer`
   - **Team:** (de momento deja "None", lo configuramos después)
   - **Organization Identifier:** `com.tunombre` (usa cualquier cosa)
   - **Bundle Identifier:** se genera automáticamente
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - **Use Core Data:** ❌ NO
   - **Include Tests:** ❌ NO
4. Haz clic en **Next**, elige dónde guardar y haz clic en **Create**.

---

## Paso 3 — Agregar los archivos del proyecto

Tienes todos los archivos Swift en la carpeta `LocalPlayer/`. Ahora hay que agregarlos a Xcode:

### 3a. Eliminar los archivos de plantilla

En el panel izquierdo de Xcode (el navegador de archivos):
- Haz clic derecho sobre `ContentView.swift` → **Delete** → **Move to Trash**

### 3b. Crear la estructura de carpetas en Xcode

En el navegador izquierdo, haz clic derecho sobre la carpeta `LocalPlayer` → **New Group** y crea estos 4 grupos:
- `Models`
- `Services`
- `ViewModels`
- `Views`

### 3c. Agregar cada archivo Swift

Para cada archivo de la carpeta `LocalPlayer/`, haz esto:

1. En Xcode: clic derecho sobre el grupo correspondiente → **Add Files to "LocalPlayer"…**
2. Navega al archivo `.swift` correcto.
3. Asegúrate de que esté marcado en **Target: LocalPlayer**.
4. Haz clic en **Add**.

Archivos y sus grupos:

| Archivo | Grupo en Xcode |
|---|---|
| `LocalPlayerApp.swift` | `LocalPlayer` (raíz) |
| `Models/Track.swift` | `Models` |
| `Services/AudioPlayerService.swift` | `Services` |
| `ViewModels/PlayerViewModel.swift` | `ViewModels` |
| `Views/ContentView.swift` | `Views` |
| `Views/LibraryView.swift` | `Views` |
| `Views/PlayerView.swift` | `Views` |
| `Views/MiniPlayerView.swift` | `Views` |

### 3d. Reemplazar Info.plist

Xcode 16 puede usar un Info.plist embebido en el proyecto. Para usar el nuestro:

1. En el navegador de Xcode, haz clic en el proyecto (icono azul arriba) → Target `LocalPlayer` → pestaña **Info**.
2. Agrega estas claves manualmente si no existen:
   - `Privacy - Documents Folder Usage Description` → `Necesitamos acceso a tus archivos de música para reproducirlos.`

---

## Paso 4 — Activar Background Audio

Esta es la clave para que la música siga sonando con la pantalla bloqueada:

1. En Xcode, haz clic en el proyecto (icono azul) → Target `LocalPlayer` → pestaña **Signing & Capabilities**.
2. Haz clic en **+ Capability** (botón arriba a la izquierda).
3. Busca **Background Modes** y haz doble clic para agregarlo.
4. En la lista que aparece, marca ✅ **Audio, AirPlay, and Picture in Picture**.

---

## Paso 5 — Configurar firma con Apple ID gratuito

1. Ve a **Signing & Capabilities** (misma pestaña del paso anterior).
2. Asegúrate de que **Automatically manage signing** esté ✅ marcado.
3. En **Team**, haz clic en el menú desplegable → **Add an Account…**
4. Inicia sesión con tu Apple ID (el mismo que usas en tu iPhone).
5. Después de iniciar sesión, selecciona tu nombre en la lista de **Team**.
6. Xcode generará automáticamente el certificado y perfil de provisión.

> **Límite de la cuenta gratuita:** puedes tener hasta 3 apps instaladas simultáneamente y caducan cada 7 días (tienes que re-instalar desde Xcode). Para mayor comodidad, considera la cuenta de pago ($99/año).

---

## Paso 6 — Conectar tu iPhone y compilar

1. Conecta tu iPhone al Mac con el cable USB.
2. En tu iPhone: aparecerá un diálogo "¿Confiar en este ordenador?" → toca **Confiar** e introduce tu código.
3. En Xcode, en la barra superior, haz clic en el selector de dispositivo (a la derecha del nombre del proyecto) y elige tu iPhone.
4. Haz clic en el botón ▶️ **Run** (o pulsa `Cmd + R`).
5. Xcode compilará e instalará la app en tu iPhone.

### Primer lanzamiento: confiar en el desarrollador

La primera vez que abras la app, iOS mostrará un error. Para solucionarlo:

1. En tu iPhone: **Ajustes → General → VPN y gestión de dispositivos**
2. Toca tu Apple ID → **Confiar en "[Tu Apple ID]"** → Confiar
3. Abre la app LocalPlayer desde la pantalla de inicio.

---

## Paso 7 — Usar la app

### Primera vez
1. Toca el botón 📁 en la esquina superior derecha.
2. Navega a la carpeta donde tienes tus canciones en la app **Archivos**.
3. Selecciona la carpeta (no un archivo individual).
4. La app cargará todas las canciones automáticamente.

### Reproducción
- **Lista:** toca cualquier canción para reproducirla.
- **Mini player:** aparece en la parte inferior con controles rápidos.
- **Player completo:** toca el mini player para abrirlo.
- **Pantalla bloqueada:** los controles aparecen en la pantalla de bloqueo.
- **AirPods:** los botones de los AirPods controlan play/pause/siguiente.

### Formatos soportados
`mp3` · `m4a` · `wav` · `aac` · `flac` · `aiff` · `opus` · `caf` · `m4b`

---

## Solución de problemas

| Problema | Solución |
|---|---|
| "No se puede abrir la app" | Confiar en el desarrollador en Ajustes (Paso 7) |
| La música para en segundo plano | Verificar que Background Audio esté activado (Paso 4) |
| "Signing certificate expired" después de 7 días | Volver a ejecutar desde Xcode (re-compila en <1 min) |
| No aparecen canciones | La carpeta debe tener archivos de audio directamente, no subcarpetas |
| No se ve la portada | El archivo MP3/M4A debe tener metadatos con artwork incrustado |

---

## Estructura del proyecto

```
LocalPlayer/
├── LocalPlayerApp.swift          — Punto de entrada (@main)
├── Models/
│   └── Track.swift               — Modelo de canción (título, artista, duración…)
├── Services/
│   └── AudioPlayerService.swift  — AVAudioPlayer + pantalla bloqueada + AirPods
├── ViewModels/
│   └── PlayerViewModel.swift     — Lógica: queue, shuffle, repeat, persistencia
├── Views/
│   ├── ContentView.swift         — Raíz de la app
│   ├── LibraryView.swift         — Lista de canciones + selector de carpeta
│   ├── PlayerView.swift          — Player completo (artwork grande, controles)
│   └── MiniPlayerView.swift      — Barra compacta en la parte inferior
└── Info.plist                    — Configuración (background audio, permisos)
```
