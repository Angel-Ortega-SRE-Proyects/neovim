# Integraciones de Neovim

Esta guía describe las integraciones que cambian el comportamiento base de la
configuración y cómo controlarlas. Los flags se pueden definir como variables
globales de Neovim o como variables de entorno.

## Flags globales

La forma general es:

```lua
vim.g.nvim_enable_<integracion> = false
```

La alternativa para una sola ejecución es:

```sh
NVIM_ENABLE_<INTEGRACION>=0 nvim
```

Una variable global de Neovim tiene prioridad sobre la variable de entorno.
Los valores reconocidos como desactivados son `false`, `0`, `no` y `off`.

| Integración | Valor predeterminado | Flag |
|---|---:|---|
| Agent Hub | habilitado | `agent_hub` |
| higpertext (`htx`) | habilitado | `htx` |
| Extensiones locales | habilitadas si existe el módulo | `extensions` |
| Copilot inline/NES | habilitado | `copilot` |
| Copilot Chat | habilitado | `copilot_chat` |
| smart-splits | habilitado | `smart_splits` |
| Git Hub | habilitado como funcionalidad base | sin flag independiente |

Para aplicar cambios hechos en Lua usa `:ConfigReload`. Los cambios de
plugins, `lazy-lock.json` o dependencias requieren reiniciar Neovim.

## Agent Hub y adaptadores

Agent Hub está habilitado por defecto y se abre con `<leader>aa` o `:Agents`.
Git Hub permanece integrado dentro de la base porque Agent Hub muestra los
cambios del repositorio y sus diffs.

El registro se encuentra en
[`lua/config/agent_adapters.lua`](../../lua/config/agent_adapters.lua). Cada
adaptador define:

- `id`: identificador estable.
- `cli`: ejecutable que debe existir en `PATH`.
- `command`: comando de Neovim.
- `module`: parser de sesiones.
- `rules`: archivos de reglas, ordenados por prioridad.
- `enabled`: permite ocultar el proveedor del Hub.

Los seis adaptadores están habilitados por defecto:

| ID | CLI | Comando | Reglas, en orden |
|---|---|---|---|
| `claude` | `claude` | `:Claude` | `CLAUDE.md`, `AGENTS.md` |
| `codex` | `codex` | `:Codex` | `AGENTS.md` |
| `opencode` | `opencode` | `:OpenCode` | `AGENTS.md`, `opencode.md` |
| `gemini` | `gemini` | `:Gemini` | `GEMINI.md`, `AGENTS.md` |
| `copilot` | `copilot` | `:CopilotCli` | `.github/copilot-instructions.md`, `AGENTS.md` |
| `grok` | `grok` | `:Grok` | `AGENTS.md` |

Un adaptador solo aparece en el Hub si está habilitado y su CLI está instalada.
Puedes desactivar uno sin tocar el parser:

```lua
vim.g.nvim_agent_adapters = {
  gemini = { enabled = false },
}
```

Para cambiar reglas, renombrar una CLI o alterar el comando:

```lua
vim.g.nvim_agent_adapters = {
  codex = {
    cli = "codex-custom",
    rules = { ".agents/codex.md", "AGENTS.md" },
  },
}
```

Estas variables deben definirse antes de cargar la configuración de plugins.
La forma más estable es ponerlas al principio de `init.lua` o exportarlas
antes de iniciar Neovim.

`:AgentRules [agente]` abre el primer archivo existente de la lista de reglas.
Si ninguno existe, abre el primer nombre para crearlo. Sin argumento usa el
agente configurado en `nvim_agent_default`, cuyo valor predeterminado es
`claude`.

```lua
vim.g.nvim_agent_default = "codex"
```

## Sesiones de agentes

Agent Hub lee las sesiones solo de los proveedores habilitados y cuya CLI está
disponible. Los parsers específicos están en `lua/config/agent_sessions/`.
OpenCode requiere además `sqlite3` para consultar su base de datos.

Los comandos disponibles son:

- `:AgentWorkspace [agente]`: agente y cambios Git lado a lado.
- `:AgentDiff [agente]`: diff de los archivos modificados por esa sesión.
- `:AgentKill [agente]`: detener una sesión activa.
- `:AgentsKillAll`: detener todas las sesiones internas.
- `:AgentRules [agente]`: abrir reglas del agente.

## higpertext

La integración está habilitada por defecto si el archivo
[`lua/plugins/htx.lua`](../../lua/plugins/htx.lua) está presente. Requiere el
ejecutable `htx` para producir resultados útiles.

Valores predeterminados:

- perfil: `software_developer`;
- asistente: el agente de `nvim_agent_default`, por defecto `claude`;
- reglas: `all`.

Se pueden cambiar así:

```lua
vim.g.nvim_agent_profile = "otro_perfil"
vim.g.nvim_agent_default = "codex"
```

Comandos:

- `<leader>hi` / `:HtxInit [perfil]`;
- `<leader>hp` / `:HtxProfile [perfil]`;
- `<leader>hl` / `:HtxRules [ids|all]`.

Para deshabilitarlo:

```lua
vim.g.nvim_enable_htx = false
```

## Sistema de extensiones locales

Las extensiones viven en `lua/extensions/enabled/*.lua`. Solo se cargan los
archivos cuyo nombre no empieza por `_`; por eso `_example.lua` es una plantilla
deshabilitada.

Una extensión mínima devuelve:

```lua
return {
  name = "mi-extension",
  description = "Descripción breve",
  setup = function(api)
    api.contribute("which_key.spec", {
      { "<leader>x", group = "Mi extensión" },
    })
  end,
}
```

Puntos de extensión actualmente disponibles:

- `i18n.translations`: añade traducciones.
- `which_key.spec`: añade grupos o descripciones de atajos.
- `git_hub.actions`: añade acciones al menú Git Hub.
- `api.on(event, callback)`: escucha eventos emitidos por el sistema.

Para deshabilitar una extensión, antepone `_` al nombre del archivo o muévelo
fuera de `lua/extensions/enabled/`. Después ejecuta `:ConfigReload`.
`:Extensions` muestra las extensiones cargadas y los errores aislados.

Una extensión con error no interrumpe el arranque: el error aparece en
`:Extensions` y como notificación.

## Copilot y Copilot Chat

Copilot inline y NES se cargan de forma diferida al entrar en Insert mode.
Requieren autenticación mediante `:Copilot auth`.

Valores predeterminados:

- sugerencias inline: activadas automáticamente;
- NES: activado automáticamente;
- `<Tab>` acepta la sugerencia visible y, si no existe, conserva el flujo de
  `nvim-cmp`;
- `<M-]>` / `<M-[>` cambian de sugerencia;
- `<C-]>` descarta la sugerencia.

Copilot Chat se carga al invocar `:CopilotChat` o cuando se solicita generar un
mensaje de commit con `<C-G>` dentro del buffer `gitcommit`.

Para deshabilitar cada integración:

```lua
vim.g.nvim_enable_copilot = false
vim.g.nvim_enable_copilot_chat = false
```

## Plataforma y terminales

[`lua/config/platform.lua`](../../lua/config/platform.lua) detecta el sistema
operativo automáticamente:

- Linux usa `xdg-open`, `/proc` y, si existe, tmux.
- macOS usa `open` y `lsof` cuando está disponible.
- Windows usa `cmd.exe`, PowerShell y el lanzador
  [`bin/nvim-fullscreen.ps1`](../../bin/nvim-fullscreen.ps1).

La integración tmux solo se activa si el ejecutable está instalado. `:Tb`
además requiere estar dentro de una sesión tmux; si no, muestra una advertencia.
La terminal interna `:Term` no depende de tmux.

Los archivos binarios y documentos se abren con la aplicación del sistema:
Linux usa `xdg-open`, macOS `open` y Windows `cmd.exe /c start`.

## Git

Git Hub está activo por defecto y no tiene un flag independiente porque Agent
Hub lo utiliza para revisar cambios. Sus entradas principales son:

- `<leader>gg`: abrir Git Hub;
- `<leader>gc`: abrir GitHub Copilot CLI;
- `:GitBack`: volver al menú Git Hub desde una vista;
- `c` en Git Hub o Agent Hub: abrir el editor de commits;
- `q` o `<Esc>`: cerrar pickers y vistas.

