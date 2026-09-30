# Extensiones

Una extensión suma configuración a esta instalación de Neovim sin editar los
módulos base. El código vive en `lua/extensions/`.

## Estructura

```text
lua/extensions/
├── init.lua           # registro y cargador
└── enabled/
    ├── _example.lua   # plantilla (se ignora: empieza con "_")
    └── mi_extension.lua
```

`init.lua` (raíz) llama `extensions.load()` al arrancar y en cada
`:ConfigReload`. Se carga por ruta absoluta, así que una extensión creada con
Neovim ya abierto se detecta al recargar.

## Integrar una extensión

1. Copia la plantilla: `cp lua/extensions/enabled/_example.lua lua/extensions/enabled/mi_extension.lua`.
2. Cambia `name` por un nombre único. Un nombre repetido se rechaza con el aviso
   `nombre duplicado`.
3. Escribe el `setup(api)` con los aportes que necesites (ver abajo).
4. Ejecuta `:ConfigReload`.
5. Comprueba con `:Extensions`: lista las cargadas (`•`) y las que fallaron (`✗`).

Para desactivarla, renombra el archivo con prefijo `_` o bórralo, y recarga.

## Extensiones en carpeta propia (fuera del repo)

Para extensiones personales con varios archivos, el registro lee las carpetas
de `vim.g.extension_roots` (por defecto
`~/Documentos/Proyects/settings/nvim-personal`). Cada extensión es una
subcarpeta con todo dentro:

```text
nvim-personal/
└── workloads/
    ├── extension.lua    # el spec (name, setup); es lo que detecta el registro
    ├── providers.lua    # módulos de apoyo
    └── view.lua
```

- La subcarpeta debe llamarse igual que el prefijo con el que se hacen los
  `require`: `require("workloads.providers")` carga `workloads/providers.lua`.
- Las carpetas que empiezan con `_` se ignoran.
- Cada extensión documenta su uso en su propio `README.md`, dentro de su
  carpeta (ejemplo: `nvim-personal/workloads/README.md`).
- En cada `:ConfigReload` se lee `extension.lua` de nuevo y se descartan los
  módulos `workloads.*` de `package.loaded`, así que los cambios se recogen sin
  reiniciar.

## Formato

```lua
return {
  name = "mi-extension",        -- obligatorio, único
  description = "opcional",     -- se muestra en :Extensions
  setup = function(api)
    -- aportes y eventos
  end,
}
```

## API de `setup(api)`

| Función | Uso |
|---------|-----|
| `api.contribute(point, value)` | Aporta `value` al punto de extensión `point`. |
| `api.on(event, fn)` | Ejecuta `fn` cuando se emite `event`. |

## Puntos de extensión

| Punto | Valor | Quién lo aplica |
|-------|-------|-----------------|
| `i18n.translations` | `{ [clave_es] = { es = "...", en = "..." } }` | El registro, al contribuir. Se usa con `require("config.i18n").t(clave_es)`. |
| `which_key.spec` | Lista de specs de which-key (`{ "<leader>x", group = "..." }`) | El registro, al contribuir. |
| `git_hub.actions` | `{ label = "...", fn = function() end }` | Pendiente: `git_mode.lua` debe leerlo con `extensions.contributions("git_hub.actions")`. Hoy el aporte se guarda pero no aparece en el menú. |

## Eventos

| Evento | Cuándo |
|--------|--------|
| `loaded` | Tras cargar todas las extensiones. |

Los módulos base pueden disparar eventos propios con
`require("extensions").emit(evento, ...)`.

## Aislamiento de errores

Cada `setup`, cada aplicación de un aporte y cada handler corre con `pcall`. Un
error se guarda en `require("extensions").errors()`, avisa con `vim.notify` y no
detiene el arranque ni a las demás extensiones.

## Ejemplo completo

```lua
return {
  name = "saludo",
  description = "Traducción, etiqueta de atajo y acción",
  setup = function(api)
    api.contribute("i18n.translations", {
      ["Hola extensión"] = { es = "Hola extensión", en = "Hello extension" },
    })
    api.contribute("which_key.spec", {
      { "<leader>x", group = "Extensiones" },
    })
    api.contribute("git_hub.actions", {
      label = "Saludar",
      fn = function() vim.notify(require("config.i18n").t("Hola extensión")) end,
    })
  end,
}
```

## Agregar un punto de extensión nuevo

1. Si el registro debe aplicar el aporte solo, agrega una función a `APPLIERS`
   en `lua/extensions/init.lua` con la clave del punto.
2. Si lo consume un módulo base, léelo con
   `require("extensions").contributions("mi.punto")` (devuelve los valores en
   orden de carga).
3. Documenta el punto en la tabla de arriba.
