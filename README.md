# claude-mods

Mods propios de [Claude Code](https://claude.com/claude-code) y los instaladores para llevarlos a cualquier equipo.

Un mod es un plugin que cambia la interfaz o el comportamiento de Claude Code: paneles, barras bajo el prompt, comandos `/…`, hooks… Este repositorio los guarda en un sitio, con su historial, y permite instalarlos de una vez en Windows, Linux, macOS y WSL.

## Mods incluidos

| Mod | Qué hace | Comandos |
|---|---|---|
| [`faf-usage-meter`](mods/faf-usage-meter) | Muestra bajo el prompt la ocupación del contexto y la cuota usada (5 h y 7 días) con sus límites, y el gasto del mes. | `/faf-usage` abre el panel con el desglose · `/faf-usage-band` muestra u oculta la barra |

## Estructura

```
claude-mods/
├── .githooks/         hooks de git con las reglas de ramas y commits
├── .github/workflows/ comprobación de esas reglas en cada PR
├── install/
│   ├── install.sh     instalador para Linux, macOS, WSL y Git Bash
│   ├── install.ps1    instalador para PowerShell (Windows; también pwsh en Linux/macOS)
│   └── install.cmd    lanzador de doble clic para install.ps1
└── mods/
    └── <nombre>/      un mod por carpeta, con su .claude-plugin/plugin.json
```

## Instalación

Clona el repositorio y ejecuta el instalador que corresponda. Sin argumentos instala y activa **todos** los mods.

**Windows**: doble clic en `install\install.cmd`, o desde PowerShell:

```powershell
.\install\install.ps1
```

**Linux, macOS o WSL**:

```bash
./install/install.sh
```

Después cierra y vuelve a abrir Claude Code. Para actualizar, haz `git pull` y vuelve a ejecutar el instalador.

### Qué hace el instalador

1. Copia cada mod a `~/.claude/mods/<nombre>`, sustituyendo la versión anterior. Si Claude Code ha generado tipos de desarrollo en `.claude-plugin/types`, los conserva.
2. Guarda una copia de `~/.claude/settings.json` en `~/.claude/backups/`.
3. Activa cada mod añadiéndolo a `env.CLAUDE_CODE_PLUGIN_DIRS` en `settings.json`. Respeta otras rutas que ya haya en esa variable y el resto de la configuración.

Si `CLAUDE_CONFIG_DIR` está definida, usa esa carpeta en lugar de `~/.claude`.

### Opciones

Los dos scripts tienen las mismas opciones:

| bash | PowerShell | Qué hace |
|---|---|---|
| `mod1 mod2` | `mod1 mod2` | instala solo esos mods |
| `--list` | `-List` | muestra los mods del repositorio y si están instalados y activos |
| `--uninstall [mods]` | `-Uninstall [mods]` | desactiva y borra esos mods (sin nombres, todos los del repositorio) |
| `--target DESTINO` | `-Target DESTINO` | dónde instalar (ver abajo) |
| `--distro NOMBRE` | `-Distro NOMBRE` | distribución de WSL; por defecto, la predeterminada |
| `--help` | `Get-Help .\install\install.ps1` | ayuda |

### Windows con WSL: instalar en los dos de una vez

Claude Code de Windows y Claude Code de WSL tienen configuraciones separadas. Con `--target` / `-Target` se elige dónde instalar:

| Destino | Desde WSL (`install.sh`) | Desde Windows (`install.ps1`) |
|---|---|---|
| `local` (por defecto) | Claude de WSL | Claude de Windows |
| `windows` | Claude de Windows | Claude de Windows |
| `wsl` | Claude de WSL | Claude de WSL |
| `both` | **ambos** | **ambos** |

```bash
./install/install.sh --target both          # desde WSL
```
```powershell
.\install\install.ps1 -Target both          # desde Windows
```

Cada script le pasa al otro la parte del otro sistema: `install.sh` usa `powershell.exe` y `install.ps1` usa `wsl.exe`. Si no se puede llegar al otro sistema, el script avisa y no instala nada.

### Requisitos

- `install.sh`: `bash` y `python3` (para editar `settings.json`). En Git Bash no hace falta `python3`, porque el trabajo lo hace `install.ps1`.
- `install.ps1`: Windows PowerShell 5.1 o PowerShell 7.
- Algunos mods necesitan haber iniciado sesión en Claude Code con una cuenta de claude.ai. Por ejemplo, `faf-usage-meter` la necesita para mostrar la cuota.

## Añadir un mod

1. Copia la carpeta del mod a `mods/<nombre>`. Debe contener `.claude-plugin/plugin.json`, con `name` igual al nombre de la carpeta.
2. Añádelo a la tabla de [Mods incluidos](#mods-incluidos).
3. Ejecuta el instalador.

La carpeta `.claude-plugin/types` que genera Claude Code al desarrollar un mod está en `.gitignore`: no se sube y se regenera sola.

## Ramas y commits

- Nada de commits en `main`: cada cambio va en una rama `tipo/descripcion` (`feat/faf-usage-meter-model`) y llega a `main` solo por PR, fusionado con squash.
- Mensajes en [Conventional Commits](https://www.conventionalcommits.org/es/), en español: `tipo(ámbito): descripción`, con la primera línea de 72 caracteres como máximo. Ejemplo: `fix(install): respeta CLAUDE_CONFIG_DIR en WSL`.
- Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`. El ámbito es el mod o la zona (`install`), y es opcional.
- El título de un PR sigue el mismo formato: al fusionar con squash, es la primera línea del commit que llega a `main`.
- Ni los commits ni los PR llevan firma de Claude (`Co-Authored-By: Claude …`, `Generated with Claude Code`).

Los hooks de `.githooks/` lo comprueban en cada commit y cada merge. Git no los activa solo: hay que hacerlo una vez en cada clon:

```bash
git config core.hooksPath .githooks
```

En cada PR, el workflow `Git rules` comprueba la rama, el título, la descripción y todos los commits, aunque quien los hizo no tuviera los hooks activados.

## Notas

- Claude Code separa las rutas de `CLAUDE_CODE_PLUGIN_DIRS` con `;` en Windows y con `:` en Linux y macOS. Los instaladores eligen el separador correcto.
- En Windows, `install.ps1` reescribe `settings.json` con la sangría de PowerShell. El contenido no cambia.
