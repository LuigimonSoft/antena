# Antena — Televisión ATSC en vivo para macOS

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md)

Antena es una aplicación nativa SwiftUI/AppKit para ver televisión abierta con un sintonizador USB **KWorld VS-ATSC 330U**. Incluye un controlador en C en espacio de usuario, reproducción con libVLC, grabación MPEG-TS opcional, gestión de canales y logotipos de emisoras.

El proyecto está dirigido a **macOS 27 o posterior en Apple Silicon** y se abre directamente en **Xcode 27**. Es un proyecto experimental para este hardware, no un controlador oficial de KWorld. La documentación principal y los identificadores del código están en inglés.

## Índice

1. [Funciones y estado](#funciones-y-estado)
2. [Requisitos](#requisitos)
3. [Compilar y ejecutar](#compilar-y-ejecutar)
4. [Ver y grabar](#ver-y-grabar)
5. [Canales y catálogos por ciudad](#canales-y-catálogos-por-ciudad)
6. [Idiomas](#idiomas)
7. [Vistas previas en Xcode](#vistas-previas-en-xcode)
8. [Controlador por consola](#controlador-por-consola)
9. [Arquitectura y archivos](#arquitectura-y-archivos)
10. [Pruebas y diagnóstico](#pruebas-y-diagnóstico)
11. [Solución de problemas](#solución-de-problemas)
12. [Preparar un repositorio público](#preparar-un-repositorio-público)
13. [Limitaciones y licencias](#limitaciones-y-licencias)

## Funciones y estado

- Vídeo y audio en vivo sin crear un archivo de vídeo; el decodificador recibe un búfer limitado en memoria.
- Inicio con logotipos, favoritos, cambio rápido e introducción numérica de canales.
- Controles que se ocultan tras 3,5 segundos de inactividad, pantalla completa, volumen y silencio.
- Selección de subtítulos cuando la emisión ofrece pistas compatibles.
- Título del programa emitido, horarios, progreso y línea de tiempo horizontal que comienza con el programa actual.
- Grabación explícita en `.ts`, reproducción desde el icono de vídeo o el botón Reproducir, acceso en Finder y retirada automática de entradas sin archivo.
- Búsqueda de ciudades de todo el mundo, indicación de frecuencia y compatibilidad del estándar, edición manual y búsqueda por antena RF 2–36.
- Interfaz en inglés, español y francés, con selección automática según macOS.
- Vistas previas SwiftUI aisladas para diseñar sin activar el sintonizador.

Se comprobó recepción con el dispositivo físico en Apple Silicon/macOS 27.0.1, incluidos ICI Radio-Canada a **503 MHz** y CBC Montréal a **515 MHz**, con reproducción de vídeo y audio. Esto no garantiza recepción en otra ubicación. Las mediciones iniciales del transporte se conservan en [reception-test.txt](docs/reception-test.txt); describen esa prueba concreta, no todas las pruebas posteriores de la aplicación.

## Requisitos

| Componente | Requisito |
| --- | --- |
| Mac | Apple Silicon; el objetivo de la app y el motor incluido son arm64 |
| Sistema | macOS 27 o posterior |
| Desarrollo | Xcode 27, herramientas de consola activas, `make`, Swift |
| Sintonizador | KWorld VS-ATSC 330U, VID/PID USB `eb1a:a316` |
| Chips | EM2883 (`0x24`), demodulador S5H1409 y sintonizador XC3028 |
| Señal | ATSC 1.0 terrestre 8VSB, 6 MHz; antena conectada |
| Motor multimedia | libVLC 3.0.24 arm64 en `Vendor/VLC/` |
| Firmware | `firmware/xc3028-v27.fw` verificado |
| Almacenamiento | Espacio para cachés y aplicación temporal, además de las grabaciones que decidas guardar |

Se necesita Internet para preparar VideoLAN, importar catálogos en línea o descargar logotipos remotos. Una aplicación ya preparada puede sintonizar una frecuencia guardada sin Internet. Los diez logotipos y el catálogo de Montréal están incluidos.

## Compilar y ejecutar

### Compilar desde la raíz del proyecto

```sh
./script/build_and_run.sh --verify
```

El script compila y abre Antena. `--verify` comprueba también el inicio del proceso; no comprueba la recepción. Para elegir una carpeta reproducible de productos de compilación:

```sh
ANTENA_DERIVED_DATA="$PWD/build/Xcode" ./script/build_and_run.sh --verify
```

Los productos se guardan en la carpeta DerivedData seleccionada. Cuando la firma necesita una copia en APFS, el script prepara `/private/tmp/Antena-Local/Antena.app` y abre esa copia. La aplicación temporal se puede recrear ejecutando el script. Consulta [los detalles de compilación](docs/BUILD.md).

### Una copia nueva del código fuente

Ejecuta los comandos desde la raíz. Prepara VideoLAN con el script y proporciona el firmware exacto descrito en [su procedencia](firmware/PROVENANCE.md) antes de verificarlo:

```sh
./script/bootstrap_vlc.sh
./script/antena_tools.sh verify-firmware
./script/build_and_run.sh
```

El script descarga la distribución oficial arm64 de VideoLAN y comprueba su SHA-256 fijado. Los binarios de VideoLAN y el firmware no se incluyen en Git. La compilación normal no descarga dependencias ausentes automáticamente. La procedencia y extracción del firmware están documentadas; no existe un comando de adquisición automática del firmware.

El firmware esperado ocupa **66 220 bytes**, versión **2.7**, con **80 imágenes**, SHA-256:

```text
0d4cfd7974a19a94f4d42eb2d160d5a3e71cca1cfa61bd2cc063cf3f36ffd32e
```

El controlador lo valida antes de sintonizar y lo carga en la RAM del sintonizador, sin escribir su EEPROM.

### Xcode

Abre `Antena.xcodeproj`, selecciona el esquema **Antena** y el destino **My Mac**. En APFS puedes compilar y ejecutar con `⌘B` y `⌘R`. El flujo local con firma ad hoc no requiere una cuenta de desarrollador de pago. Para compilar directamente en Xcode, coloca DerivedData en APFS con espacio suficiente. El script también gestiona las compilaciones que necesitan una copia en APFS.

`script/Tools/ProjectGenerator.swift` regenera el proyecto de manera determinista. Si modificas la estructura o configuración generada, actualiza también el generador. Excluye los metadatos `._*` y muestra el helper USB y las pruebas sin añadirlos al objetivo de la app.

## Ver y grabar

El programa actual y una línea de tiempo horizontal de seis horas aparecen cuando la emisora transmite datos ATSC PSIP utilizables. Títulos, horarios y progreso proceden de la señal, sin grabar vídeo. Consulta [los detalles de la guía y sus límites de codificación](docs/PROGRAM_GUIDE.md).

Al arrancar, Antena sintoniza el primer canal de la biblioteca guardada y muestra el inicio. Pulsa una tarjeta para cambiar de canal o **Ver canal** para centrarte en el vídeo. Mueve el puntero o pulsa una tecla para recuperar los controles ocultos.

La grabación comienza únicamente después de pulsar **Grabar** y confirmar un archivo de destino. Guarda el transporte MPEG recibido sin recodificar, desde la posición del directo de ese momento. No sobrescribe archivos. Detener la grabación mantiene el directo; cambiar de canal o cerrar la aplicación finaliza la grabación activa. El archivo contiene el transporte recibido, que puede incluir varios programas y datos, no un MP4 exportado de un único programa.

El icono de vídeo y el botón **Reproducir** inician la reproducción. Las entradas sin archivo se eliminan al abrir esta vista, al volver a activar Antena y en comprobaciones periódicas mientras permanece abierta. Los archivos existentes no se borran.

En **Grabaciones** puedes reproducir entradas de la biblioteca o mostrarlas en Finder. **Archivo → Abrir grabación…** permite abrir archivos externos. Los subtítulos dependen de la emisión y del decodificador; Antena no los genera. Cambiar el idioma de la interfaz no traduce el audio ni los subtítulos emitidos.

| Atajo | Acción |
| --- | --- |
| `←` / `→`, Re Pág / Av Pág | Canal anterior / siguiente |
| Dígitos y `.` | Introducir un canal virtual, como `6.1` |
| `L` | Último canal |
| `F` | Pantalla completa |
| `R` | Iniciar / detener grabación |
| `M` | Activar / desactivar silencio |
| `C` | Activar / desactivar la primera pista de subtítulos disponible |
| `Esc` | Salir de pantalla completa o volver al inicio |
| `⌘O` | Abrir una grabación |
| `⌘,` | Ajustes |

El menú Televisión también ofrece comandos de canales y grabación con sus atajos visibles.

## Canales y catálogos por ciudad

En **Canales**, escribe una ciudad de cualquier país, opcionalmente con el país o la región, y pulsa **Buscar e importar**. Wikipedia y Wikidata identifican el lugar y las fichas terrestres disponibles. Solo se utiliza RF o MHz publicados; el número virtual nunca se convierte en RF. La importación conserva los canales y favoritos existentes.

Importar un catálogo no comprueba la señal. **Buscar canales** utiliza el sintonizador físico en RF 2–36 e interrumpe el directo. Las frecuencias nuevas pueden aparecer identificadas por RF hasta que las renombres. Las entradas manuales usan MHz; la consola del controlador usa Hz.

El catálogo incluido de Montréal se documentó el 22 de octubre de 2026. Es un punto de partida, no una garantía de recepción de todas las emisoras:

| Virtual | Emisora | RF | MHz |
| --- | --- | --- | --- |
| 2.1 | ICI Radio-Canada · CBFT-DT | 19 | 503 |
| 6.1 | CBC Montréal · CBMT-DT | 21 | 515 |
| 10.1 | TVA Montréal · CFTM-DT | 11 | 201 |
| 12.1 | CTV Montréal · CFCF-DT | 12 | 207 |
| 15.1 | Global Montréal · CKMI-DT-1 | 15 | 479 |
| 17.1 | Télé-Québec · CIVM-DT | 26 | 545 |
| 29.1 | Savoir média · CFTU-DT | 29 | 563 |
| 35.1 | Noovo Montréal · CFJP-DT | 35 | 599 |
| 47.1 | ICI Télé · CFHD-DT | 31 | 575 |
| 62.1 | Citytv Montréal · CJNT-DT | 17 | 491 |

La búsqueda mundial depende de la cobertura y formato de la fuente pública; no se garantizan listas completas para todas las ciudades. Las fichas sin frecuencia o con un estándar incompatible quedan solo como catálogo y no se pueden sintonizar con este receptor ATSC 1.0. Montréal utiliza el catálogo incluido si la consulta no está disponible. Consulta [los detalles del catálogo](docs/CHANNELS.md) y [la atribución de logotipos](docs/channel-logo-sources.json).

## Idiomas

El inglés es el idioma de desarrollo y de respaldo. Antena sigue de forma predeterminada la lista de idiomas preferidos de macOS y selecciona inglés, español o francés, incluidas variantes regionales como `es-CA` y `fr-CA`. Si ninguna preferencia compatible coincide, utiliza inglés.

**Antena → Ajustes → Idioma de la interfaz** permite elegir **Seguir macOS**, **English**, **Español** o **Français**. Los cambios manuales se aplican al volver a abrir la app. Los identificadores, nombres de vistas previas y claves de localización permanecen en inglés. Las traducciones están en `Antena/Resources/en.lproj`, `es.lproj` y `fr.lproj`, visibles como `Localizable.strings` en Xcode. Los nombres de las emisoras conservan su escritura oficial.

## Vistas previas en Xcode

Selecciona un archivo de `Antena/Views` y activa **Editor → Canvas** (`⌥⌘↩`). Pulsa **Resume** si Xcode pausa las vistas. Hay vistas previas del inicio, reproductor, canales, grabaciones, logotipos y tarjetas; los ajustes de idioma aparecen desactivados en su vista previa.

Las vistas usan datos de ejemplo en memoria y una ilustración como fondo de vídeo. No abren el USB, graban vídeo, consultan el catálogo ni modifican las preferencias guardadas de canales. Ejecuta la aplicación para recibir televisión real.

## Controlador por consola

El helper utiliza IOKit/IOUSBLib en espacio de usuario; no instala una extensión de kernel ni expone una cámara AVFoundation. Estos comandos lo compilan y permiten, en orden, consultar la ayuda, leer descriptores USB, identificar el frontend, sintonizar, capturar e inspeccionar el transporte:

```sh
./script/build_driver.sh --help
./script/build_driver.sh
./script/build_driver.sh --frontend-probe
./script/build_driver.sh --tune 515000000
mkdir -p recordings
./script/build_driver.sh --capture 515000000 30 recordings/cbc.ts
./script/antena_tools.sh inspect-ts recordings/cbc.ts
```

El archivo de captura no debe existir y su carpeta debe existir. La duración admitida es de **1 a 3600 segundos**. `Ctrl-C` detiene la captura y cancela las lecturas USB pendientes. `--stream HZ` entrega MPEG-TS continuo por stdout y mensajes por stderr; la app lo utiliza para el directo. Evita abrir el mismo sintonizador desde la aplicación y la consola al mismo tiempo.

El ejecutable es `build/kworld-tv`; `build/kworld-probe` es un alias de compatibilidad. `--transport-test` es un diagnóstico USB, no una prueba de recepción. Códigos de salida: **0** éxito, **1** fallo USB/firmware/señal/captura, **2** dispositivo desconectado, **64** uso incorrecto. `./script/build_and_run.sh` sin argumentos abre la interfaz; utiliza `build_driver.sh` para consultar los descriptores.

## Arquitectura y archivos

```text
Sintonizador USB → kworld-tv → stdout MPEG-TS → búfer RAM limitado → libVLC → vídeo/audio
                                   └──── grabación explícita → archivo .ts
```

El búfer circular del puente C ocupa `188 × 32768` bytes (unos 5,9 MiB). Si el decodificador se retrasa, se descartan bytes antiguos en lugar de permitir crecimiento ilimitado. La app espera al cierre del helper antes de resintonizar y finaliza la grabación activa al salir.

```text
Antena.xcodeproj/             Proyecto Xcode y esquema compartido Antena
Antena/
  App/                       Ciclo de vida y comandos
  Models/                    Channel, Recording, CaptionTrack
  Stores/                    Biblioteca persistente
  Services/                  Sintonizador, reproducción, grabación, catálogo
  Views/                     Pantallas y componentes SwiftUI
  Support/                   Tema, localización y datos de vistas previas
  Bridge/                    Interfaz C de libVLC y búfer circular
  Resources/                 Iconos, logotipos y en/es/fr.lproj
Sources/                     Helper USB en C y transporte MPEG-TS
Tests/                       Pruebas independientes Swift y C
script/                      Compilación, dependencias, verificación y firma
firmware/                    Procedencia del firmware y binario local
Vendor/VLC/                  Dependencia local VideoLAN (fuera de Git)
Reference/                   Referencias y avisos del controlador original
docs/                        Guías técnicas y evidencia de recepción
build/                       Helper generado, cachés y registro de compilación
dist/                        Entregables locales, si se generan
```

`LibraryStore` guarda canales, ciudad y referencias de grabaciones en UserDefaults, con identificador `local.antena.television`. Las grabaciones permanecen en las rutas que eliges; la biblioteca no las copia a otra ubicación. Las entradas cuyos archivos ya no existen se quitan automáticamente mientras la vista de grabaciones está abierta. El icono de vídeo también permite reproducir. Las consultas de catálogos y logotipos se realizan a Wikipedia/Wikimedia; los logotipos pueden utilizar la caché de disco de URLSession. El vídeo en vivo utiliza RAM salvo que inicies una grabación explícitamente.

## Pruebas y diagnóstico

Ejecuta desde la raíz después de preparar las dependencias. Las pruebas Swift son ejecutables independientes, no un objetivo XCTest de Xcode:

Ajusta `APP_PATH` a la aplicación compilada que quieras probar. El ejemplo usa `ANTENA_DERIVED_DATA="$PWD/build/Xcode"`; si el script preparó una copia firmada, utiliza la ruta de esa copia.

```sh
APP_PATH="$PWD/build/Xcode/Build/Products/Debug/Antena.app"
make test
./script/antena_tools.sh self-test

xcrun swiftc Antena/Support/Localization.swift Antena/Models/Channel.swift \
  Antena/Services/CityCatalog.swift Tests/CityCatalogTests.swift \
  -o /private/tmp/AntenaCityCatalogTests
/private/tmp/AntenaCityCatalogTests

xcrun swiftc Antena/Support/Localization.swift Antena/Models/Channel.swift \
  Antena/Stores/LibraryStore.swift Tests/LibraryStoreTests.swift \
  -o /private/tmp/AntenaLibraryTests
/private/tmp/AntenaLibraryTests

xcrun swiftc Antena/Services/RecordingWriter.swift Tests/RecordingWriterTests.swift \
  -o /private/tmp/AntenaRecordingWriterTests
/private/tmp/AntenaRecordingWriterTests

xcrun swiftc Antena/Support/Localization.swift Tests/LocalizationTests.swift \
  -o /private/tmp/AntenaLocalizationTests
/private/tmp/AntenaLocalizationTests "$APP_PATH/Contents/Resources"
```

Cubren ensamblado y continuidad del transporte con sanitizadores, identidad del firmware, plan RF y compatibilidad del catálogo, combinación/persistencia de la biblioteca y aislamiento de vistas previas, grabación explícita/sin sobrescritura/escrituras concurrentes, y selección de idioma/traducciones/parámetros de formato. Añade `--network` a `AntenaCityCatalogTests` para consultar Montréal realmente; esa prueba opcional depende del servicio externo.
Las pruebas de programación cubren descubrimiento PSIP, conversión horaria, cambio de programa y metadatos dañados. Las pruebas de biblioteca comprueban que se retiran las referencias ausentes de forma persistente y se conservan los vídeos existentes.

Para probar el reproductor con una muestra existente y guardar contadores sin grabar televisión en vivo:

```sh
open -n "$APP_PATH" --args \
  --sample /absolute/path/sample.ts \
  --diagnostics /private/tmp/antena-diagnostics.json
```

Sustituye la ruta de muestra por una ruta absoluta existente. El JSON contiene estado y contadores de vídeo, audio y bytes. Compilar correctamente o leer descriptores no demuestra recepción RF. Los errores de compilación están en **`build/antena-build.log`**. `./script/build_and_run.sh --debug` inicia LLDB; `--logs` o `--telemetry` abre la aplicación y muestra sus registros.

## Solución de problemas

| Problema | Comprobación |
| --- | --- |
| No encuentra el sintonizador | Confirma VID/PID compatible, conexión y adaptador USB; reconecta |
| No puede abrir el dispositivo | Cierra otro cliente del sintonizador; un entorno aislado puede denegar IOKit |
| Sin sincronización o vídeo | Comprueba antena, cobertura y frecuencia RF real; prueba otra emisora |
| Faltan dependencias | Prepara `Vendor/VLC/` y el firmware exacto; consulta el registro de compilación |
| Firma incorrecta en ExFAT | Usa el script; firma la copia preparada en APFS |
| Disco lleno | Libera espacio para la compilación y los temporales del sistema |
| Importación vacía | Prueba el nombre inglés de la ciudad, frecuencias manuales o búsqueda por antena |
| Falta un logotipo | Los de Montréal están incluidos; los remotos dependen de Wikimedia e Internet |
| No abre una grabación | Comprueba si se movió o borró el archivo original |
| Idioma incorrecto | Revisa Ajustes y el orden de idiomas de macOS; cierra y vuelve a abrir Antena |
| Canvas vacío | Selecciona una vista con `#Preview`, muestra Canvas y reanuda; revisa sus errores |

## Preparar un repositorio público

`.gitignore` excluye archivos generados, binarios descargados, grabaciones, ajustes personales y archivos de trabajo de agentes. Para validar los archivos públicos y crear un paquete limpio:

```sh
./script/antena_tools.sh prepare-github --check
./script/antena_tools.sh prepare-github
```

Se generan `dist/Antena-source.zip` y `dist/github-manifest.txt`. Revisa el manifiesto antes de publicar. Estos comandos no crean commits ni suben archivos. Consulta [los detalles de publicación](docs/PUBLISHING.md), incluida la diferencia entre archivos ya seguidos por Git y archivos ignorados.

## Limitaciones y licencias

- Recepción **ATSC 1.0 8VSB** para la revisión identificada. No implementa NTSC analógico, QAM por cable ni ATSC 3.0.
- No se han validado Intel, otros identificadores/revisiones USB ni recepción completa de todas las emisoras del catálogo.
- Hay un solo sintonizador: no se implementan dos frecuencias RF simultáneas, grabación programada ni pausa/retroceso del directo. La guía en vivo cubre la frecuencia sintonizada cuando hay datos PSIP utilizables.
- Es una compilación de desarrollo local con firma ad hoc, sin notarización Developer ID ni paquete para App Store. El helper se ejecuta fuera de App Sandbox.
- El controlador y el puente C incluyen avisos **GPL-2.0-only**. Consulta [LICENSE](LICENSE) y conserva los avisos originales de `Reference/`.
- Las bibliotecas/plugins de VideoLAN mantienen sus propios términos; consulta `Vendor/VLC/README-VideoLAN.txt` después de prepararlos y el [código de VLC](https://code.videolan.org/videolan/vlc).
- El firmware extraído tiene procedencia separada y no queda cubierto por la licencia del código; consulta [PROVENANCE.md](firmware/PROVENANCE.md). No es una publicación oficial de firmware para macOS.
- Los logotipos y marcas de emisoras conservan sus respectivos derechos y [atribución](docs/channel-logo-sources.json).

Más información: [guía de la aplicación](docs/APP.md), [catálogos](docs/CHANNELS.md), [detalles de compilación](docs/BUILD.md), [herramientas nativas](docs/TOOLS.md), [evidencia de recepción](docs/reception-test.txt).

## Acerca de y DMG de lanzamiento

**Antena → Acerca de Antena** muestra la autoría de **Luigimonsoft**, [su perfil de GitHub](https://github.com/luigimonsoft), fecha del proyecto **23 de octubre de 2026**, versión, compilación y créditos.

Ejecuta `./script/build_release.sh` para crear un DMG de Release localmente. El flujo de GitHub Actions **Build release DMG** se ejecuta manualmente o con etiquetas `v…` y guarda el DMG y su suma de verificación como artefacto de Actions. Configura primero el secreto obligatorio `XC3028_FIRMWARE_BASE64`. El paquete predeterminado tiene firma ad hoc y no está notarizado; no se publica automáticamente como GitHub Release. Consulta [la configuración y el estado de distribución](docs/RELEASES.md).
