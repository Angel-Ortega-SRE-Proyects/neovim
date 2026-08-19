# Gestión de archivos en Neovim

Guía rápida de comandos para crear y eliminar archivos sin salir de Neovim.

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
