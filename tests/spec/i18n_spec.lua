local i18n = require("config.i18n")

describe("idiomas de la interfaz", function()
  it("ofrece español e inglés y traduce las vistas principales", function()
    local previous = i18n.lang

    i18n.lang = "es"
    assert.equals("CENTRO DE AGENTES", i18n.t("AGENT HUB"))

    i18n.lang = "en"
    assert.equals("AGENT HUB", i18n.t("AGENT HUB"))
    assert.equals("REGISTERED PROJECTS", i18n.translate_line("PROYECTOS REGISTRADOS"))

    i18n.lang = previous
  end)

  it("registra el selector y el comando directo", function()
    assert.equals(2, vim.fn.exists(":LanguageSelect"))
    assert.equals(2, vim.fn.exists(":LanguageSet"))
  end)
end)
