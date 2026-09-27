# Proyectos en Neovim

Cada proyecto se abre en una pestaña independiente con su propia carpeta raíz y
explorador. La barra superior muestra el número de pestaña y el nombre del
proyecto; los números se actualizan al abrir o cerrar pestañas.

## Abrir y crear

- `<leader>p` o `:Projects`: elegir un proyecto guardado; `Enter` lo abre o
  cambia a su pestaña.
- `<leader>pn` o `:ProjectNew`: pedir carpeta y nombre, y abrirla como proyecto.
- `:ProjectNew ruta/al/proyecto`: crear/registrar y abrir esa ruta.
- En el selector, `<C-n>` inicia un proyecto nuevo y `<C-a>` agrega una ruta a
  la lista sin abrirla.

## Cambiar y nombrar

- `gt` / `gT`: cambiar a la pestaña siguiente/anterior.
- `:tabnext` / `:tabprevious`: cambiar de pestaña mediante comandos.
- `:ProjectRename nombre`: nombrar el proyecto de la pestaña actual. Sin
  argumento, abre el campo para escribir el nombre.
- En el selector, `<C-r>` cambia el nombre y `<C-x>` quita el proyecto de la
  lista de recientes, sin borrar sus archivos.

Los nombres propios se guardan en `stdpath('state')/projects.json`.

## Configuración específica por proyecto

Cada proyecto puede incluir un archivo `.nvim.lua` en su raíz. Neovim lo carga
automáticamente al entrar al proyecto, dejando sus opciones y autocmds aislados
de los demás proyectos.

Ejemplo:

```lua
vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.expandtab = true
```

La raíz actual queda disponible en `vim.g.project_root` y cada cambio de
proyecto emite el evento `User ProjectChanged`.

## Buffer activo

El buffer activo recibe una configuración según su tipo:

- código: sin wrap y sin spell-check;
- Markdown: wrap por palabras, spell-check y ancho de 100 columnas;
- commits Git: wrap y ancho de 72 columnas.

El proyecto puede sobrescribir cualquier ajuste desde `.nvim.lua` con
`vim.opt_local`, por ejemplo:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.textwidth = 88
    vim.opt_local.colorcolumn = "88"
  end,
})
```
