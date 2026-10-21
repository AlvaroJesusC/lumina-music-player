---
trigger: always_on
description: Reglas de optimización, rendimiento de audio y mejora de UI/Layout para lumina_player
---

# Reglas Activas para lumina_player

1. **Consulta de Skills:**
   Revisar y ejecutar las directrices de las skills en `.agent/skills/` correspondientes a la tarea (especialmente `flutter-performance`, `adaptive-layout`, `widget-composition`, `motion-and-haptics` y `design-system-structure`).

2. **Rendimiento y Cero Lag en Audio:**
   - Constructores `const` en todo subárbol estático.
   - Aislar la barra de progreso y el contador de tiempo de audio; nunca hacer `setState()` global en `full_player_screen.dart` por actualizaciones de posición.
   - Optimizar la carga de carátulas (`cached_artwork.dart`) con tamaños acotados (`cacheWidth`/`cacheHeight`).
   - Cancelar y liberar suscripciones a streams (`StreamSubscription`) y controladores en `dispose()`.

3. **Mejora de UI y Layout:**
   - Transiciones fluidas entre el mini-reproductor y la pantalla completa.
   - Micro-interacciones con físicas suaves y feedback háptico en controles clave.
   - Presentación visual moderna con fondos dinámicos y sombras pulidas sin saturar el hilo de pintado.
