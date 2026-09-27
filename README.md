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

Usa `:ThemeSelect` o `<leader>uc` para elegir entre verde, ámbar, cian y
violeta. La elección se conserva al volver a abrir Neovim. `:ThemeReload`
vuelve a aplicar el tema activo.

En la línea de comandos, escribe por ejemplo `:T` y pulsa `Tab` para abrir
las sugerencias. Con el menú abierto, `↓` y `↑` cambian el comando mostrado;
`Ctrl-Y` acepta la opción sin ejecutarla y `Enter` la ejecuta. `Esc` cancela
el comando y cierra el menú en una pulsación. En `:ThemeSelect`, `Esc` cancela
la elección de inmediato. El tema activo aparece en la barra inferior.

## Reproducibilidad

- `lazy-lock.json` **debe** commitearse: fija el commit exacto de cada plugin.
- Para actualizar plugins de forma controlada: `:Lazy update` y commitear el nuevo lock file.
- Formateo de Lua con [stylua](https://github.com/JohnnyMorganz/StyLua) (`.stylua.toml`).

## Espacio de trabajo de agentes

`<leader>aw` (o `:AgentWorkspace [agente]`) muestra un agente a la izquierda
y el estado de cambios Git a la derecha, en dos columnas que ocupan toda la
pantalla. El panel derecho se actualiza con `r`; las sesiones siguen vivas al
volver al modo flotante.

## Próximos pasos

Este es el punto de partida estándar. Sobre esta base se irán integrando módulos adicionales
(DAP, testing, linters específicos por lenguaje, snippets propios, etc.).
