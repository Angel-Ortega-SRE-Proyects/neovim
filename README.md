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
lua/plugins/
  colorscheme.lua         -- tokyonight
  treesitter.lua          -- resaltado/indentado por AST
  telescope.lua           -- fuzzy finder
  lsp.lua                 -- mason + lspconfig
  cmp.lua                 -- autocompletado
  editor.lua              -- lualine, gitsigns, nvim-tree, which-key, etc.
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

## Reproducibilidad

- `lazy-lock.json` **debe** commitearse: fija el commit exacto de cada plugin.
- Para actualizar plugins de forma controlada: `:Lazy update` y commitear el nuevo lock file.
- Formateo de Lua con [stylua](https://github.com/JohnnyMorganz/StyLua) (`.stylua.toml`).

## Espacio de trabajo de agentes

`<leader>aa` (o `:Agents`) abre el Agent Hub con las sesiones locales de los
agentes. Además de las terminales administradas por Neovim, muestra las
sesiones interactivas guardadas por Codex con la etiqueta `Codex · ...`; al
abrir una, se reanuda mediante `codex resume`. Pulsa `r` para volver a leer la
lista de sesiones. Las sesiones de Codex aparecen agrupadas por ruta de
proyecto; pulsa `Enter` o `p` sobre el grupo para abrir esa ruta en su pestaña
de proyecto y revisar sus archivos y cambios Git. En cualquier panel del Hub,
`Ctrl+A` seguido de una flecha cambia su tamaño; puedes mantener la flecha
presionada para repetir el ajuste. `Ctrl+Flecha` cambia el panel enfocado.

`<leader>aw` (o `:AgentWorkspace [agente]`) muestra un agente a la izquierda
y el estado de cambios Git a la derecha, en dos columnas que ocupan toda la
pantalla. El panel derecho se actualiza con `r`; las sesiones siguen vivas al
volver al modo flotante.

En AgentHub, `g` agrega repositorios al panel Git sin reemplazar los anteriores.
Los archivos modificados aparecen agrupados por repositorio; `r` actualiza todos
los repositorios observados.

## Modo Git global

- `<leader>gg` (`Espacio` + `g` + `g`) abre Git Hub en una sola ventana con commits,
  ramas, estado, diffs, historial del repositorio y stage.
- `<leader>gc` (`Espacio` + `g` + `c`) abre GitHub Copilot CLI.

Las acciones Git que antes estaban repartidas en varios atajos se encuentran
dentro del modo Git para mantener una entrada global única.

Desde un picker o Diffview, usa `q`, `<Esc>` o `:GitBack` para volver a Git Hub.

La creación de commits en AgentHub (`c`) y Git Hub usa un buffer `gitcommit`;
Copilot puede sugerir el mensaje y `Tab` lo acepta. Guarda con `:w` o `<C-s>`.

## Próximos pasos

Este es el punto de partida estándar. Sobre esta base se irán integrando módulos adicionales
(DAP, testing, linters específicos por lenguaje, snippets propios, etc.).
