# Antena para macOS 27

Aplicación SwiftUI/AppKit con proyecto nativo **Antena.xcodeproj** y esquema compartido
**Antena**. Se abre directamente en Xcode 27. El objetivo de esta versión es Apple
Silicon, con macOS 27 o posterior.

## Abrir y ejecutar

1. Abre `Antena.xcodeproj` en Xcode.
2. Selecciona el esquema **Antena**, destino **My Mac**.
3. Pulsa Run. No se necesita una cuenta de desarrollador para la firma local.
4. Conecta el KWorld VS-ATSC 330U y la antena.

También puedes usar `./script/build_and_run.sh`. El ejecutable de recepción por
línea de comandos continúa disponible mediante `./script/build_driver.sh`.

Las dependencias ya se prepararon en este espacio de trabajo. Para una copia nueva,
primero ejecuta `./script/bootstrap_vlc.sh` y proporciona el firmware descrito en
`firmware/PROVENANCE.md`. Los binarios de VideoLAN y el firmware no se incluyen en Git.
La compilación muestra un error explícito si falta alguno; no los descarga por su cuenta.

## Uso

- **Inicio:** abre el primer canal de la biblioteca guardada de forma automática y muestra la emisión detrás
  del dashboard. Las tarjetas cambian el canal sin abrir otra ventana.
- **Ver canal:** entra al reproductor. Tras 3,5 segundos sin actividad se ocultan
  controles y cursor. Mover el ratón o pulsar una tecla los recupera.
- **Canales:** permite añadir, editar y quitar frecuencias. Las frecuencias están
  en MHz; el número virtual (por ejemplo 6.1) es una etiqueta de navegación.
- **Buscar canales:** recorre RF 2–36 y conserva las frecuencias donde el
  demodulador logra sincronización. Interrumpe el directo porque hay un solo
  sintonizador. Los canales nuevos se identifican inicialmente por RF y pueden
  renombrarse. La búsqueda no interpreta la guía de programación.
- **Grabar:** abre un panel para elegir el archivo `.ts`. No sobrescribe archivos.
  Puede detenerse sin detener el directo. Cambiar de canal finaliza la grabación
  actual y la añade a la biblioteca.
- **Grabaciones:** permite reproducir un archivo guardado o mostrarlo en Finder.
  El menú Archivo también permite abrir una grabación externa.
- **Subtítulos:** el menú CC enumera las pistas que el motor encuentra en la
  emisión, incluidos los closed captions que esta transporte. Su disponibilidad
  depende de la señal y del programa. No se generan ni se inventan subtítulos.

Atajos: flechas izquierda/derecha o Re Pág/Av Pág para canales; `L` para el último;
`F` para pantalla completa; `R` para grabar; `M` para silenciar; `C` para activar
la primera pista de subtítulos o desactivarla; `Esc` para salir de pantalla completa
 o volver al inicio. Los dígitos y el punto permiten introducir un canal, como 6.1.

## Reproducción en vivo sin grabar

El helper `kworld-tv --stream HZ` entrega MPEG-TS por su salida estándar y envía
los mensajes por la salida de error. La app recibe esa tubería y alimenta un búfer
circular de aproximadamente 6 MB en RAM. libVLC lee el búfer mediante callbacks;
no se crea un archivo de vídeo ni una lista HLS en disco.

Solo una acción explícita de grabación abre un archivo de vídeo. El archivo es una
copia del transporte recibido, sin recodificación, conservando vídeo, audio y datos
transportados. La grabación comienza en la posición del directo en ese momento.

El búfer está limitado: si el decodificador no consume a tiempo se descartan los
bytes más antiguos en lugar de crecer sin límite. El transporte puede resincronizarse
posteriormente. Los contadores de diagnóstico permiten detectar descartes.

La app termina y espera al proceso anterior antes de sintonizar otra frecuencia,
para evitar abrir el USB simultáneamente. Al cerrar la aplicación detiene la
captura, despierta las lecturas del decodificador y cierra la grabación activa.

## Motor multimedia y procedencia

Se utiliza **libVLC 3.0.24, arm64**, extraído de la distribución oficial de VideoLAN:

- https://download.videolan.org/pub/videolan/vlc/3.0.24/macosx/vlc-3.0.24-arm64.dmg
- SHA-256: `64a89d93cdd30b0e97131743e246373db82d6826ea882d265d46d74b136da2b7`

La huella se cotejó con el archivo `.sha256` publicado en el mismo directorio.
Las bibliotecas, plugins y datos se incorporan al bundle; no se instala ni se abre
la aplicación VLC. Las cabeceras originales y el README de VideoLAN se conservan
en `Vendor/VLC`. El código fuente de VLC está disponible en
https://code.videolan.org/videolan/vlc y sus términos acompañan la distribución.

El proyecto no está firmado con Developer ID ni notarizado para distribución.
Usa firma ad hoc para desarrollo local. No es una entrega para la Mac App Store.
El acceso USB del helper se realiza fuera del App Sandbox.

## Verificación de desarrollo

- `make test`: transporte MPEG-TS, continuidad y verificación del firmware.
- `xcodebuild -project Antena.xcodeproj -scheme Antena -configuration Debug -derivedDataPath build/Xcode build`.
- Argumento opcional `--sample /ruta/archivo.ts`: probar el reproductor con una
  muestra existente cuando no se dispone de señal.
- Argumento opcional `--diagnostics /ruta/informe.json`: guardar contadores del
  decodificador para verificar vídeo, audio y memoria sin grabar la emisión.

Los canales de Montreal precargados son frecuencias candidatas; solo se muestran
como comprobados cuando se ha recibido o sincronizado señal. La app no contiene
programas, películas ni horarios ficticios para rellenar el diseño.

## Vistas previas en Xcode

Abre `Antena.xcodeproj` y selecciona un archivo de `Antena/Views`. Activa **Editor → Canvas** (⌥⌘↩). Las declaraciones `#Preview` muestran el inicio, el reproductor, los canales, las grabaciones y sus componentes. Si Xcode pausa el Canvas, pulsa **Resume**.

Las vistas previas usan canales y grabaciones de muestra en memoria: no activan el sintonizador, no consultan el catálogo por Internet y no modifican las preferencias guardadas. El fondo de vídeo es una ilustración; para ver televisión real ejecuta la aplicación.

## Languages

English is the development language and fallback. Antena automatically selects English, Spanish or French using the macOS preferred language list, including regional variants such as `es-CA` and `fr-CA`. Unsupported languages fall back to English when no supported language is preferred.

Open **Antena → Settings** (`⌘,`) to follow macOS or choose English, Español or Français. Manual changes apply on the next launch. This changes the interface, not the broadcast audio or captions.

Source identifiers, developer preview names and localization keys are in English. Translations are separate native Xcode resources under `Antena/Resources/{en,es,fr}.lproj/Localizable.strings`. Station names and saved channel metadata are preserved. All three languages use the same format arguments.

Localization verification (after building):

```sh
xcrun swiftc Antena/Support/Localization.swift Tests/LocalizationTests.swift -o /private/tmp/AntenaLocalizationTests
/private/tmp/AntenaLocalizationTests /private/tmp/Antena-Local/Antena.app/Contents/Resources
```

## Programa actual y siguientes

El inicio y el reproductor muestran el programa actual, horario y progreso cuando llegan datos PSIP utilizables. La línea de tiempo horizontal cubre seis horas y permite consultar el título y horario de cada emisión. No necesita grabar vídeo. La disponibilidad y el texto dependen de la emisora; se indica cuando faltan datos. Consulta [la implementación y sus límites](PROGRAM_GUIDE.md).
