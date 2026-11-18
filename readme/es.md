# CharSync

[English](../README.md) · [Deutsch](de.md) · [Français](fr.md) · [Español](es.md) · [Português](pt-BR.md) · [Italiano](it.md) · [Русский](ru.md) · [한국어](ko.md) · [简体中文](zh-CN.md) · [繁體中文](zh-TW.md)

Configura un personaje a tu gusto y dale los mismos ajustes a todos los demás. CharSync te muestra, ajuste por ajuste, qué va a cambiar (antes → después) y qué hace cada cambio, para que puedas dejar fuera lo que no quieras.

Para **WoW Forever**. En el idioma de tu cliente del juego: inglés, alemán, francés, español, portugués, italiano, ruso, coreano y chino (simplificado y tradicional).

## Cómo funciona

1. Inicia sesión con el personaje cuyos ajustes deben aplicarse a todos, abre `/charsync` y haz clic en **«Guardar como plantilla general»**.
2. Para macros y barras de acción, guarda una **plantilla de clase** una vez por clase: solo van a personajes de la misma clase.
3. Cuando otro personaje inicia sesión, CharSync abre una ventana de revisión: cada diferencia con antes → después y una explicación. Desmarca lo que no quieras y haz clic en **«Aplicar marcados»**.

Un addon no puede escribir archivos de otros personajes, así que la plantilla se guarda para toda la cuenta y se aplica cuando cada personaje inicia sesión.

## Qué puede sincronizar

- Opciones de interfaz que WoW guarda por personaje (barras de acción adicionales, barra de recursos personal, nivel de misión, opciones de los marcos de banda, mapa del mundo, minimapa)
- Ventanas de chat (nombre, tamaño de fuente, fondo, tipos de mensaje, canales) y colores del chat
- El diseño activo del Modo Edición
- Asignación de teclas
- Qué addons están activados
- Perfiles de addons que guardan sus ajustes con la biblioteca Ace3
- Macros del personaje y barras de acción: solo misma clase
- Posiciones de ventanas (ventanas movidas, de WoW y de addons) y posiciones de los botones del minimapa

Los gráficos, el sonido, la mayoría de las opciones de interfaz y casi todos los ajustes de addons ya son de toda la cuenta en WoW.

## Opciones

- Activa o desactiva secciones enteras.
- Desmarca un ajuste concreto para no sincronizarlo nunca más (para todos los personajes).
- Guarda una plantilla automáticamente (desactivado por defecto): una vez por minuto y al cerrar sesión, solo si algo ha cambiado.
- Aplica las plantillas nuevas sin preguntar.
- Sección «Ajustes de la cuenta» (desactivada por defecto): al marcarla, cada cambio en ajustes que valen para todos los personajes (ajustes de addons y opciones de WoW de la cuenta) aparece con su valor anterior; acéptalo o restablécelo uno a uno.
- Restablece cada entrada por separado. En el personaje plantilla, los cambios desde el guardado pasan uno a uno a la plantilla (**«A la plantilla»**). La última aplicación se puede deshacer (**«Deshacer»**).
- Contrae secciones; la casilla del encabezado marca todo lo que contiene.
- **«Ajustes excluidos»** muestra todo lo que excluiste: márcalo para recuperarlo.

Comandos: `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`, `/charsync icon` (recupera el botón del minimapa)
