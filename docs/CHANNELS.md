# Catálogo de ciudades y logotipos

En **Canales → Televisión abierta de tu ciudad**, escribe una ciudad de cualquier país y pulsa **Buscar e importar**. Puedes añadir país o región para distinguir lugares homónimos. Wikipedia y Wikidata identifican la ciudad y las fichas de televisión terrestre publicadas en sus páginas de medios o televisión. La búsqueda admite lugares de todo el mundo, pero la cobertura de estas fuentes no garantiza todas las emisoras de cada ciudad.

Montréal incluye un catálogo local de diez emisoras, consultado el 22 de octubre de 2026. Funciona también sin conexión. La búsqueda por Internet actualiza las frecuencias y obtiene enlaces de los logotipos. La cobertura mundial no es exhaustiva: depende de la cobertura y el formato del catálogo público. Si no existe una ficha compatible, la aplicación informa del problema y permite añadir frecuencias manualmente o buscar por antena.

La importación combina las emisoras por indicativo o por número y frecuencia; conserva identificadores, favoritos y recepción comprobada si no cambia la frecuencia. No borra canales previamente añadidos. Importar no prueba la recepción; solo la sincronización real del sintonizador marca una emisora como comprobada.

| Canal virtual | Emisora | RF | MHz |
| --- | --- | --- | --- |
| 2.1 | CBFT-DT · ICI Radio-Canada | 19 | 503 |
| 6.1 | CBMT-DT · CBC | 21 | 515 |
| 10.1 | CFTM-DT · TVA | 11 | 201 |
| 12.1 | CFCF-DT · CTV | 12 | 207 |
| 15.1 | CKMI-DT-1 · Global | 15 | 479 |
| 17.1 | CIVM-DT · Télé-Québec | 26 | 545 |
| 29.1 | CFTU-DT · Savoir média | 29 | 563 |
| 35.1 | CFJP-DT · Noovo | 35 | 599 |
| 47.1 | CFHD-DT · ICI Télé | 31 | 575 |
| 62.1 | CJNT-DT · Citytv | 17 | 491 |

Fuentes: [emisoras de Montréal](https://en.wikipedia.org/wiki/Media_in_Montreal), fichas individuales enlazadas en el catálogo y [tabla de frecuencias de Montréal](https://www.tvchannellists.com/w/List_of_over-the-air_television_stations_in_Montr%C3%A9al). En caso de discrepancia se consulta la ficha individual: TVA usa RF 11, aunque la tabla general de Wikipedia todavía indica 10.

Los logotipos identifican a sus respectivas emisoras; sus marcas pertenecen a sus titulares. `channel-logo-sources.json` contiene las páginas originales de Wikimedia, autores y condiciones disponibles en los metadatos de cada archivo. La licencia del código de Antena no cambia los derechos de esas imágenes. Los diez logotipos de Montréal se incluyen como recursos; los de otras ciudades se cargan por HTTPS desde Wikimedia mediante la caché de URLSession. Ninguna de estas operaciones graba el vídeo.

Pruebas: `Tests/CityCatalogTests.swift` verifica el plan RF, la diferencia entre RF y canal virtual, la compatibilidad con datos anteriores y las diez emisoras iniciales. La opción `--network` consulta realmente Montréal y exige diez emisoras y una respuesta en línea.

## Búsqueda internacional y compatibilidad

Se comprobaron consultas en Montréal, Los Ángeles, Ciudad de México, Londres, Madrid y Tokio. Son ejemplos de cobertura de las fuentes, no garantía de recepción en esas ubicaciones. No se utiliza la ubicación del Mac ni se solicita permiso de geolocalización: la ciudad procede del texto escrito por el usuario.

Cada ficha guarda su ciudad, fuente y, cuando se conoce, estándar de televisión. Las frecuencias no publicadas se representan internamente con valor cero y se muestran como «Frecuencia sin confirmar», nunca como una frecuencia RF inventada. Los números virtuales de países distintos no se interpretan con el plan norteamericano. La conversión RF a Hz se utiliza solo para fichas ATSC de Canadá, Estados Unidos y México; en otros casos solo se conservan MHz explícitos.

Este KWorld solo recibe ATSC 1.0. Las fichas DVB-T/T2, ISDB-T, DTMB, ATSC 3.0 o de estándar desconocido pueden aparecer en el catálogo, pero sus botones de reproducción están desactivados. El cambio secuencial de canales las omite. El editor permite indicar frecuencia y estándar manualmente, sin que esa edición añada soporte de hardware para otros estándares.

La importación no cambia la emisora que se está viendo. Se combinan entradas por indicativo o URL de fuente y se evita mezclar emisoras distintas que carecen de número o frecuencia. Los logotipos se obtienen únicamente de campos de imagen de identificación de la emisora; no se sustituyen por fotografías arbitrarias de la página.

Si no se identifica un lugar o no se encuentran fichas terrestres verificables, se informa del problema y no se sustituyen los canales por un catálogo nacional o una lista ficticia. El catálogo incluido de Montréal sigue disponible sin conexión. Los nombres ingleses de las ciudades ofrecen la cobertura más amplia de las páginas consultadas.
