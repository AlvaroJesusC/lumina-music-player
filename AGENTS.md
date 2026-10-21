# Reglas y Estándares de Optimización, Audio y UI/Layout para lumina_player

> **IMPORTANTE PARA EL AGENTE DE IA (ANTIGRAVITY / COPILOT / CURSOR):**
> Este proyecto cuenta con 40 skills especializadas instaladas localmente en `.agent/skills/`.
> **SIEMPRE**, antes de implementar funcionalidades, optimizar código, diseñar o ajustar pantallas y componentes de audio en `lumina_player`, DEBES consultar y seguir rigurosamente las directrices de las skills correspondientes.

---

## 🗺️ Mapa de Skills Obligatorias para este Proyecto

| Tarea / Dominio | Skill(s) Obligatoria(s) en `.agent/skills/` |
| :--- | :--- |
| **Rendimiento, 60/120 FPS, Scrubber/Streams de Audio sin Lag, Isolates** | `flutter-performance` |
| **Layout Adaptativo (Mini-Player flotante, Full Player Sheet, Orientaciones)** | `adaptive-layout` |
| **Composición de Widgets (Carátulas, Cola de Reproducción, Controles de Audio)** | `widget-composition` |
| **Animaciones, Micro-interacciones y Físicas (Transición de Sheet, Vinilo/Cover)** | `motion-and-haptics` |
| **Diseño Visual de Alto Impacto (Glassmorphism, Temas Oscuros, Dynamic Colors)** | `design-system-structure` |
| **Gestos Táctiles (Swipe para cambiar canción, Scrubbing suave)** | `custom-canvas-and-gestures` |
| **Estados de Buffering, Biblioteca Vacía y Permisos de Almacenamiento** | `ui-states-and-feedback` |
| **Sintaxis Moderna Dart 3 sin Código Redundante** | `dart3-idioms-and-coding-standards` |
| **Seguridad Asíncrona (Stream subscriptions, dispose de players, leaks)** | `async-safety` |
| **Arquitectura Limpia y Modular** | `flutter-architecture`, `project-structure-and-packages` |

---

## ⚡ 1. Directivas de Rendimiento y Optimización (Audio & UI)
*Referencia principal: `.agent/skills/flutter-performance/SKILL.md`*

1. **Aislamiento del Scrubber y Streams de Posición:**
   - La posición del audio (`Stream<Duration>` de `just_audio` / `audio_service`) emite eventos continuos. **PROHIBIDO** hacer `setState()` en `full_player_screen.dart` o en todo el árbol de widgets para actualizar la barra de tiempo.
   - Usar `StreamBuilder` localizado exclusivamente alrededor de `ProgressBar` o el widget de tiempo transcurrido con `const` en todo el resto de la pantalla.
2. **Optimización y Caché de Carátulas (Artwork):**
   - En `cached_artwork.dart` y en las listas de canciones de `music_library_page.dart`:
     - Usar siempre tamaño acotado (`size` en `on_audio_query`, o `cacheWidth`/`cacheHeight`).
     - No decodificar imágenes a resolución nativa en listas largas para evitar fugas de memoria o caídas de frames en el scroll.
3. **Listas Perezosas Obligatorias:**
   - Las canciones, álbumes y playlists deben renderizarse siempre con `ListView.builder` o `Slivers`.
4. **Liberación Estricta de Recursos (`dispose`):**
   - Cancelar subscripciones a `StreamSubscription` (`positionStream`, `playerStateStream`), pausar animaciones cuando el reproductor esté oculto o pausado, y limpiar controladores de animación.
5. **Cálculos Pesados y Consultas de Archivos en Segundo Plano:**
   - Filtros de búsqueda de canciones masivas o agrupaciones de playlists deben realizarse fuera del hilo principal si el catálogo es extenso.

---

## 🎨 2. Directivas de UI, Layout y Ergonomía (Reproductor de Música)
*Referencias: `.agent/skills/adaptive-layout/`, `widget-composition/`, `motion-and-haptics/`, `design-system-structure/`*

1. **Jerarquía Visual y Mini-Player:**
   - El reproductor persistente inferior (*Mini-Player*) debe ser discreto, accesible y transicionar fluidamente hacia el reproductor completo (`full_player_screen.dart`) mediante curvas suaves (`Curves.fastOutSlowIn`).
2. **Estética y Acabado No Genérico:**
   - Diseño moderno para amantes de la música: carátulas con bordes redondeados y sombras sutiles, efectos de desenfoque/glassmorphism de fondo basados en la carátula actual, y tipografía limpia.
3. **Micro-interacciones y Feedback Háptico:**
   - Respuesta háptica al presionar Play/Pause, cambiar de pista o activar modo aleatorio/repetición.
   - Animación sutil de escala o rotación en la carátula durante la reproducción/pausa.
4. **Estados Claros:**
   - Manejo elegante de permisos de audio denegados con botón de acción directa.
   - Skeletons o placeholders bonitos mientras se escanean las canciones del dispositivo.
