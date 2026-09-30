-- Plantilla de extensión. Los archivos que empiezan con "_" se ignoran:
-- copia este a otro nombre (p. ej. mi_config.lua) para activarla.
return {
  name = "ejemplo",
  description = "Plantilla: traducción + atajo + acción de Git Hub",
  setup = function(api)
    -- Traducciones (las usa config.i18n.t con la clave en español).
    api.contribute("i18n.translations", {
      ["Hola extensión"] = { es = "Hola extensión", en = "Hello extension" },
    })

    -- Etiquetas de which-key.
    api.contribute("which_key.spec", {
      { "<leader>x", group = "Extensiones" },
    })

    -- Acción para el menú Git Hub (la consume git_mode cuando se conecte).
    api.contribute("git_hub.actions", {
      label = "Acción de ejemplo",
      fn = function() vim.notify(require("config.i18n").t("Hola extensión")) end,
    })

    -- Evento: se dispara cuando terminan de cargar todas las extensiones.
    api.on("loaded", function() end)
  end,
}
