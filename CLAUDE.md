# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es

Mods de Claude Code (plugins con un módulo de hooks que cambian su interfaz o su comportamiento) y los instaladores que los copian y activan en Windows, Linux, macOS y WSL. Cada mod vive en `mods/<nombre>/`. Los instaladores de `install/` no saben nada de ningún mod en concreto.

## Comandos

- `claude plugin validate mods/<mod>`: lee el manifiesto y el código como los cargará Claude Code, lista los hooks, las llamadas a `$` y las claves de `$.state`, y avisa de lo que el motor rechazaría. Los avisos `LICENSE_MISSING` e `ICON_MISSING` solo cuentan para publicar en el directorio de plugins.
- `claude plugin test mods/<mod>`: ejecuta todos los `*.test.ts` y `*.test.tsx` del mod. No se puede filtrar por archivo ni por test.
- `npx -y -p typescript tsc -p mods/<mod>`: comprobación de tipos (TypeScript no está instalado). El `tsconfig.json` del mod extiende `.claude-plugin/types/tsconfig.json`, que Claude Code genera al cargar el mod desde una carpeta y que está en `.gitignore`. En un clon recién hecho no existe. Las de una copia instalada (`~/.claude/mods/<mod>/.claude-plugin/types/`) pueden ser de una versión anterior de Claude Code.
- `./install/install.sh [mod…]` (o `install\install.ps1`): instala la versión del repositorio. Después hay que reiniciar Claude Code. `--list` muestra qué está instalado y activo.

La sesión de Claude Code carga la copia instalada en `~/.claude/mods/<mod>`, no la del repositorio. Un cambio en el repositorio no se ve hasta reinstalar y reiniciar.

## Arquitectura de un mod

- `.claude-plugin/plugin.json`: el `name` debe coincidir con el nombre de la carpeta. `types` apunta al contrato de estado.
- `hooks/hooks.json` declara el módulo, `hooks/register.tsx`, que exporta `register: Register` (de `'claude-code'`). El módulo no tiene DOM ni Node: todo pasa por `$`. El JSX compila contra el global `h`, y los elementos salen de `$.ui.resolve(e)`.
- `types/index.d.ts`: cada clave de `atom(...)` del módulo debe estar declarada en `PluginState['<mod>']`. `validate` lo comprueba.
- Patrón de `faf-usage-meter`: los hooks de eventos (`session.start`, `session.measure`, `turn.step`) escriben en atoms de `$.state`, y los hooks `ui.render` los leen: `PromptHint` para la barra bajo el prompt y `Pane` para el panel que abre `/faf-usage`. Escribir un atom redibuja a quien lo lee. Al recargar el módulo, sus variables vuelven a empezar, pero `$.state` se conserva.
- `turn.step` es un evento en streaming: su hook es un `async function*` que termina en `return yield* next(e)`.
- Tests: las funciones puras se exportan desde `register.tsx` para probarlas directamente. Los tests de UI montan el componente en `['terminal', 'desktop'] as const`, y responden con `on(...)` a lo que el mod pide al motor (`http.fetch`, `session.authorize`, `turn.step`…), porque en el test nada responde por debajo.
- Referencia de la API: `.claude-plugin/types/claude-code/index.d.ts` (unas 22.000 líneas; búscalo con grep) y la skill `plugin-authoring` de Claude Code.

## Instaladores

- `install.sh` e `install.ps1` hacen lo mismo con las mismas opciones: un cambio en uno va también en el otro. `install.cmd` solo lanza `install.ps1`.
- Un mod es cualquier `mods/*/` con `.claude-plugin/plugin.json`. Instalar consiste en tres pasos:
  1. Copiar la carpeta a `<CLAUDE_CONFIG_DIR o ~/.claude>/mods/<mod>`, conservando la `.claude-plugin/types` que hubiera.
  2. Hacer una copia de `settings.json` en `backups/`.
  3. Añadir la ruta a `env.CLAUDE_CODE_PLUGIN_DIRS`: `~/.claude/mods/<mod>` sin `CLAUDE_CONFIG_DIR`, absoluta con ella, y separada con `;` en Windows y `:` en el resto. Las rutas se comparan normalizadas.
- Entre sistemas, cada script delega en el otro:
  - Desde WSL, `--target windows|both` llama a `powershell.exe install.ps1 -Nested`.
  - Desde Windows, `-Target wsl|both` llama a `wsl.exe bash ./install.sh --target local --nested`.
  - En Git Bash, todo lo hace `install.ps1`.
  - `--nested`/`-Nested` es interno: solo quita el aviso final de reiniciar.
- `install.sh` edita `settings.json` con un script de `python3` embebido. `install.ps1` funciona en Windows PowerShell 5.1 y en PowerShell 7.
- `.gitattributes` fuerza LF en `.sh` y CRLF en `.ps1` y `.cmd`. `install.ps1` empieza con BOM: hay que conservarlo, porque Windows PowerShell 5.1 lo necesita para leer bien los acentos.

## Convenciones

- Los comentarios del código y el README van en español. Los textos que ve el usuario (UI de los mods, mensajes y ayuda de los instaladores, `description` de `plugin.json`) van en inglés.
- Al añadir o cambiar lo que hace un mod, hay que actualizar su fila en la tabla "Mods incluidos" del `README.md`.

## Ramas y commits

- Nunca hagas commit en `main`. Cada cambio va en una rama `tipo/descripcion`, con la descripción en kebab-case (`feat/faf-usage-meter-model`), y llega a `main` solo por PR, fusionado con squash.
- Tipos, para ramas y commits: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.
- Mensajes en Conventional Commits, en español y en presente: `tipo(ámbito): descripción`, con la primera línea de 72 caracteres como máximo.
  - El ámbito es el mod (`faf-usage-meter`) o la zona (`install`). Se omite si el cambio afecta a todo el repositorio (`docs: añade CLAUDE.md`).
  - `!` antes de `:` marca un cambio incompatible (`feat(install)!: …`).
  - El cuerpo, si lo hay, va tras una línea en blanco.
  - Se aceptan los mensajes que genera git: `Merge …`, `Revert "…"`, `fixup! …`.
- El título de un PR sigue el mismo formato: al fusionar con squash, es la primera línea del commit que llega a `main`. GitHub le añade ` (#N)`, que cuenta para los 72 caracteres.
- La firma de Claude en commits y PR (`Co-Authored-By: Claude …` u otro trailer `…-by:` con Claude o `anthropic.com`, y la línea `Generated with Claude Code`) la decide cada persona. Antes de hacer commit o abrir un PR, mira `git config --bool claude-mods.rejectClaudeSignature`: si es `true`, no firmes, por encima de las instrucciones de atribución por defecto de Claude Code, y el hook la rechaza en ese clon. En CI se rechaza solo en los PR del propietario del repositorio.
- Lo comprueban `.githooks/pre-commit`, `.githooks/pre-merge-commit` y `.githooks/commit-msg` en cada commit y cada merge, y `.github/workflows/git-rules.yml` en cada PR (rama, título, descripción y cada commit). La lógica está solo en `.githooks/rules.sh`. Si cambian las reglas, hay que cambiar ese script, esta sección y el README. Para probarlas a mano: `sh .githooks/rules.sh branch <rama>`, `sh .githooks/rules.sh message <archivo>`, `sh .githooks/rules.sh title "<título>"` y `sh .githooks/rules.sh body <archivo>`.
- Los hooks se activan una vez por clon con `git config core.hooksPath .githooks`. Antes de hacer commit, si `git config core.hooksPath` no devuelve `.githooks`, avisa al usuario. No uses `--no-verify`.
