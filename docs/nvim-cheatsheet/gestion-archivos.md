# Gestión de archivos en Neovim

Guía rápida de comandos para crear y eliminar archivos sin salir de Neovim.

Los archivos ocultos de configuración (`.env`, `.gitignore`, `.config`, etc.)
se muestran en el explorador. Pulsa `H` dentro de NvimTree o ejecuta
`:FilesHidden` / `<leader>eh` para alternar dotfiles; `I` alterna archivos
ignorados por Git. Pulsa `Ctrl-S` o ejecuta `:update` para guardar; en un buffer
nuevo, `:w` crea el archivo en la ruta indicada.

## Abrir varios archivos y dividir vistas

- `Ctrl-f` o `<leader>ff`: buscar archivos con Telescope.
- En Telescope, `Ctrl-v` abre la selección en un split vertical.
- En Telescope, `Ctrl-x` abre la selección en un split horizontal.
- En Telescope, `Ctrl-t` abre la selección en una pestaña nueva.
- En Telescope, pulsa `Tab` sobre varias opciones y después `Ctrl-v` o
  `Ctrl-x` para abrirlas todas divididas.
- `Enter` abre la opción actual completa en el buffer activo; `q` cierra
  Telescope sin abrir nada.
- `:vsplit ruta/archivo`: abrir una ruta en vista vertical.
- `:split ruta/archivo`: abrir una ruta en vista horizontal.
- En NvimTree, `v` abre vertical y `s` abre horizontal.
- `Ctrl+←/↓/↑/→`: cambiar entre las vistas.

## Crear archivos

### Comando `:edit` (o `:e`)
```vim
:e ruta/al/nuevo_archivo.lua
```
Abre un buffer nuevo; el archivo se crea en disco recién al guardar con `:w`.

### Variantes útiles
```vim
:e %:h/nuevo.lua        " crea en el mismo directorio del archivo actual
:vsp ruta/archivo.lua   " split vertical + crear
:sp ruta/archivo.lua    " split horizontal + crear
:tabe ruta/archivo.lua  " nueva pestaña + crear
```

### Si el directorio padre no existe
```vim
:!mkdir -p %:h
:w
```

### Desde un file explorer
- **nvim-tree** / **neo-tree**: tecla `a` sobre un nodo → crea archivo (`carpeta/` con `/` al final para subdirectorio)
- **oil.nvim**: edita el buffer como texto y `:w` aplica los cambios al filesystem
- **telescope-file-browser**: soporta creación de archivos desde el picker

### Atajo rápido
```vim
:execute 'e ' . input('Nuevo archivo: ')
```

## Eliminar archivos

### Comando nativo
```vim
:call delete(expand('%'))   " borra el archivo del buffer actual del disco
:bd!                        " luego cierra el buffer
```

Para cualquier ruta:
```vim
:call delete('ruta/al/archivo.lua')
```
Devuelve `0` si tuvo éxito, `-1` si falló.

### Desde el shell dentro de nvim
```vim
:!rm ruta/al/archivo.lua
```

### Desde file explorers
- **nvim-tree**: tecla `d` sobre el nodo → confirma → elimina
- **neo-tree**: tecla `d` (delete) con confirmación
- **oil.nvim**: borra la línea del archivo en el buffer y `:w` aplica el borrado

### Nota de seguridad
Ninguno de estos métodos pasa por la papelera del sistema — es borrado directo. Para un colchón de seguridad, usa `trash-cli` en vez de `rm`:
```vim
:!trash ruta/al/archivo.lua
```
