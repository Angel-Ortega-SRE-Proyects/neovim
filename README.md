# Neovim Config

Configuración reproducible base de Neovim, gestionada con [lazy.nvim](https://github.com/folke/lazy.nvim).

## Estructura

```
init.lua                 -- entry point
lua/config/
  options.lua             -- vim.opt
  keymaps.lua             -- keymaps globales
  autocmds.lua            -- autocomandos
  lazy.lua                -- bootstrap de lazy.nvim
  platform.lua            -- diferencias entre Linux, macOS y Windows
  agent_adapters.lua      -- registro de CLIs, reglas y proveedores de agentes
lua/plugins/
  colorscheme.lua         -- tokyonight
  treesitter.lua          -- resaltado/indentado por AST
  telescope.lua           -- fuzzy finder
  lsp.lua                 -- mason + lspconfig
  cmp.lua                 -- autocompletado
  editor.lua              -- lualine, gitsigns, nvim-tree, which-key, etc.
  ai_cli.lua              -- Agent Hub (se conserva como funcionalidad base)
lazy-lock.json             -- versiones exactas de plugins (se genera al instalar)
```

## Instalación

```bash
ln -s "$(pwd)" ~/.config/nvim
nvim
```

## Abrir Neovim a pantalla completa

Desde la raíz del proyecto:

```bash
./bin/nvim-fullscreen
```

El lanzador detecta GNOME Terminal, Kitty y Alacritty. Para usarlo desde
cualquier carpeta, crea un enlace en `~/.local/bin`:

```bash
ln -s "$(pwd)/bin/nvim-fullscreen" ~/.local/bin/nvim-fullscreen
```

Al abrir Neovim por primera vez, `lazy.nvim` se clona automáticamente e instala todos los plugins
fijados en `lazy-lock.json`, garantizando el mismo entorno en cualquier máquina.

Con Neovim ya abierto, usa `:ConfigReload`. Al terminar mostrará la ruta de la
configuración recargada. Para cambios de plugins, reinicia Neovim después de
recargar.

## Temas y comandos

Usa `:ThemeSelect` o `<leader>uc` para abrir el selector flotante. Incluye ocho
presets: `carbon` (oscuro neutro), `verde` (oliva suave), `ambar` (cálido),
`cian` (frío), `ocaso` (malva), `pizarra` (azul gris), `arena` (tierra) y
`violeta` (claro). `carbon` usa el fondo carbón `#1c1c1c`. La elección se
conserva al volver a abrir Neovim y también actualiza el fondo del dashboard.

En la línea de comandos, escribe por ejemplo `:T` y pulsa `Tab` para abrir
las sugerencias. Con el menú abierto, `↓` y `↑` cambian el comando mostrado;
`Ctrl-Y` acepta la opción sin ejecutarla y `Enter` la ejecuta. `Esc` cancela
el comando y cierra el menú en una pulsación. En `:ThemeSelect`, `j/k`, las
flechas o `1-8` cambian la selección; `Enter` aplica y `q`/`Esc` cancela. El
tema activo aparece en la barra inferior.

## Idioma de la interfaz

La interfaz incluye español (`es`, predeterminado) e inglés (`en`). Usa
`:LanguageSelect` o `<leader>ul` para abrir el selector, o ejecuta
`:LanguageSet es` / `:LanguageSet en`. La elección se guarda en el estado de
Neovim y se conserva al volver a abrirlo.

## Reproducibilidad

- `lazy-lock.json` **debe** commitearse: fija el commit exacto de cada plugin.
- Para actualizar plugins de forma controlada: `:Lazy update` y commitear el nuevo lock file.
- Formateo de Lua con [stylua](https://github.com/JohnnyMorganz/StyLua) (`.stylua.toml`).

## Espacio de trabajo de agentes

`<leader>aa` (o `:Agents`) abre el Agent Hub con las sesiones locales de los
agentes y todos los proyectos registrados por `:Projects`. Al seleccionar un
proyecto, `Enter` muestra las acciones compactas para abrirlo o consultar sus
agentes; `p` lo abre directamente en su pestaña propia. La lista muestra las
sesiones activas de ese proyecto y hasta cinco aparecen resumidas; las
que están ejecutando una tarea usan un indicador
animado y los que esperan usan un punto fijo. El nombre se mantiene compacto
en la lista y el hover muestra ruta,
último acceso y estado de cambios. Además, las sesiones interactivas guardadas
por cada agente aparecen agrupadas por ruta y se reanudan mediante `Enter`.

Solo se activan los agentes cuya CLI está instalada en `$PATH`; lo mismo aplica
a la lista `NUEVA INSTANCIA`. Fuentes de sesiones (`lua/config/agent_sessions/`):

| Agente | Almacenamiento leído | Reanudar |
|--------|----------------------|----------|
| Claude Code | `~/.claude/projects/*/*.jsonl` (estado en `~/.claude/sessions/`) | `claude --resume <id>` |
| Codex | `~/.codex/sessions/**/*.jsonl` | `codex resume <id>` |
| OpenCode | `~/.local/share/opencode/opencode.db` (requiere `sqlite3`) | `opencode -s <id>` |
| Gemini | `~/.gemini/tmp/*/chats/*.jsonl` | `gemini --resume <id>` |
| Copilot | `~/.copilot/session-state/*/` | `copilot --resume=<id>` |
| Grok | `~/.grok/sessions/*/*/summary.json` | `grok --resume <id>` |

`:Grok` abre Grok CLI igual que `:Claude`, `:Codex` o `:Gemini`.
La barra inferior concentra los comandos disponibles del Hub. En cualquier
panel, `Ctrl+A` o `Ctrl+Space`, luego `r` y una flecha, cambia su tamaño; puedes
mantener la flecha presionada para repetir el ajuste. `Ctrl+Flecha` cambia el
panel enfocado.

En la lista de proyectos, `g` fija o desfija el proyecto seleccionado; los
fijados aparecen primero con el prefijo `g`. También puedes usar
`:ProjectPin [ruta]`.

`<leader>aw` (o `:AgentWorkspace [agente]`) muestra un agente a la izquierda
y el estado de cambios Git a la derecha, en dos columnas que ocupan toda la
pantalla. El panel derecho se actualiza con `r`; las sesiones siguen vivas al
volver al modo flotante.

En AgentHub, `g` agrega repositorios al panel Git sin reemplazar los anteriores.
Los archivos modificados aparecen agrupados por repositorio; `r` actualiza todos
los repositorios observados.

### Adaptadores y reglas de agentes

Los proveedores se registran en
[lua/config/agent_adapters.lua](lua/config/agent_adapters.lua). Ahí puedes
cambiar la CLI, el comando de Neovim, el parser de sesiones y la prioridad de
los archivos de reglas sin modificar Agent Hub.

`:AgentRules [agente]` abre el primer archivo de reglas existente del proyecto.
Por ejemplo, Codex usa `AGENTS.md`, Claude prioriza `CLAUDE.md` y Copilot
prioriza `.github/copilot-instructions.md`. Si no existe ninguno, abre el primer
nombre configurado para crearlo.

También puedes cambiar el agente y perfil predeterminados antes de cargar la
configuración:

    vim.g.nvim_agent_default = "codex"
    vim.g.nvim_agent_profile = "software_developer"
    vim.g.nvim_agent_adapters = {
      codex = { rules = { "AGENTS.md", ".agents/rules.md" } },
    }

Agent Hub y Git forman parte de la base actual. Las extensiones de agentes,
integraciones adicionales y proveedores nuevos se mantienen aislados mediante
este registro para poder extraerlos después como módulos independientes.

## Plataformas

La configuración detecta Linux, macOS y Windows para abrir archivos externos,
consultar el directorio de las terminales y seleccionar el monitor del sistema.
tmux se activa solo cuando está instalado; si no existe, se usan splits y
terminales internas de Neovim. En Windows puedes usar
[bin/nvim-fullscreen.ps1](bin/nvim-fullscreen.ps1) desde PowerShell.

Consulta la guía completa de activación, desactivación y valores predeterminados
en [docs/nvim-cheatsheet/integraciones.md](docs/nvim-cheatsheet/integraciones.md).

## Modo Git global

- `<leader>gg` (`Espacio` + `g` + `g`) abre Git Hub en una sola ventana con commits,
  ramas, estado, diffs, historial del repositorio y stage.
- `<leader>gc` (`Espacio` + `g` + `c`) abre GitHub Copilot CLI.

Las acciones Git que antes estaban repartidas en varios atajos se encuentran
dentro del modo Git para mantener una entrada global única.

Desde un picker o Diffview, usa `q`, `<Esc>` o `:GitBack` para volver a Git Hub.

La creación de commits en AgentHub (`c`) y Git Hub usa un buffer `gitcommit`;
Copilot puede sugerir el mensaje y `Tab` lo acepta. Guarda con `:w` o `<C-s>`.

## Pruebas

La suite (plenary/busted) cubre núcleo, proyectos, Git, barras y temas,
sesiones de agentes, Agent Hub y plugins. Se ejecuta en un entorno aislado
(`HOME` y `XDG_*` temporales), así que nunca toca tus proyectos, tema ni
sesiones reales:

```sh
tests/run.sh                            # toda la suite
tests/run.sh tests/spec/git_spec.lua    # un solo archivo
```

| Archivo | Cubre |
|---------|-------|
| `core_spec.lua` | opciones, atajos globales, autocmds, perfiles de buffer |
| `projects_spec.lua` | registro, fijado, alias, pestañas y comandos de proyectos |
| `git_spec.lua` | `config.git`, Git Hub y commits reales en repos temporales |
| `ui_spec.lua` | statusline, franja superior, monitor, temas, `:Commands`, cuotas |
| `agent_sessions_spec.lua` | los seis proveedores de sesiones y el agregador |
| `agent_hub_spec.lua` | ciclo de vida de agentes y vistas del Agent Hub |
| `plugins_spec.lua` | specs de lazy, terminales, `htx`, recarga en caliente |

Los helpers compartidos viven en `tests/spec_helpers.lua`. Cada cambio de
comportamiento debe venir con su test.

## Próximos pasos

Este es el punto de partida estándar. Sobre esta base se irán integrando módulos adicionales
(DAP, testing, linters específicos por lenguaje, snippets propios, etc.).
