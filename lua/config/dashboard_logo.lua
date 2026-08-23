-- Símbolo de infinito animado: tubo 3D (curva figure-eight/lemniscata)
-- renderizado a dígitos 1/0 vía z-buffer + sombreado, con una luz que
-- recorre la curva. dashboard.lua llama a M.render(width, height,
-- light_position) en cada tick de un timer para obtener un frame nuevo (la
-- luz avanza y los 1/0 cambian de posición), dando el efecto de giro. Los
-- highlights de color van aparte, en dashboard.lua.
local M = {}

-- WIDTH coincide con el ancho del logo de texto "DEVOPS" (74 columnas) a
-- propósito: snacks.nvim centra cada línea del header según su propio
-- ancho, así que si el bloque del infinito y el del texto miden lo mismo,
-- ambos quedan centrados con el mismo offset y dashboard.lua puede ubicar
-- el bloque del infinito anclándose en la línea (fija, nunca en blanco)
-- del logo de texto en vez de tener que adivinar en cuál línea del frame
-- animado (que sí puede quedar vacía según por dónde va la luz).
M.WIDTH = 74
M.HEIGHT = 16
M.SPEED = 0.09 -- radianes que avanza la luz por tick

local PATH_STEPS = 220
local TUBE_STEPS = 18

local CURVE_A = 2.6 -- amplitud en X de la lemniscata
local CURVE_B = 1.5 -- amplitud en Y
local TUBE_RADIUS = 0.55
local TILT = 0.6 -- inclinación de cámara (rad) para que se note el volumen 3D
local CAMERA_Z = 6.0

local LIGHT_WIDTH = 0.35 -- ancho del pico de brillo alrededor de light_position
local TAIL_WIDTH = 0.9 -- cola de brillo detrás de la luz

local TAU = math.pi * 2

local function normalize(x, y, z)
  local len = math.sqrt(x * x + y * y + z * z)
  if len < 1e-9 then
    return 0, 0, 0
  end
  return x / len, y / len, z / len
end

local function cross(ax, ay, az, bx, by, bz)
  return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function circular_distance(a, b)
  return ((a - b + math.pi) % TAU) - math.pi
end

-- Rotación de cámara: inclina el plano XY sobre el eje X, así el tubo
-- (que en su propio espacio es plano en Z=0 salvo por el grosor) se ve
-- con volumen en vez de una silueta chata.
local function tilt(x, y, z)
  local cs, sn = math.cos(TILT), math.sin(TILT)
  return x, y * cs - z * sn, y * sn + z * cs
end

--- Devuelve una lista de `height` strings de `width` caracteres ("1", "0"
--- o " "). "1" = punto iluminado (cerca de light_position), "0" =
--- estructura del tubo sin iluminar, " " = fondo.
function M.render(width, height, light_position)
  local screen = {}
  local zbuffer = {}
  local litbuffer = {}
  for i = 1, width * height do
    screen[i] = " "
    zbuffer[i] = -1e9
  end

  local scale = math.min(width / 6.0, height / 2.2)
  local scale_x = scale * 1.0
  local scale_y = scale * 1.0

  for i = 0, PATH_STEPS - 1 do
    local t = i / PATH_STEPS * TAU

    -- Curva madre (lemniscata de Gerono) y su tangente.
    local cx = CURVE_A * math.sin(t)
    local cy = CURVE_B * math.sin(t) * math.cos(t)
    local dx = CURVE_A * math.cos(t)
    local dy = CURVE_B * math.cos(2 * t)
    local tx, ty, tz = normalize(dx, dy, 0)

    -- Marco ortonormal (T, N, B) para extrudir el tubo alrededor de la curva.
    local bx, by, bz = 0, 0, 1
    local nx, ny, nz = cross(bx, by, bz, tx, ty, tz)
    nx, ny, nz = normalize(nx, ny, nz)
    bx, by, bz = cross(tx, ty, tz, nx, ny, nz)

    -- Brillo de la luz que recorre la curva: pico gaussiano en
    -- light_position + una cola tenue detrás (mismo criterio que el script
    -- de referencia: head + 0.4*tail).
    local dist = circular_distance(t, light_position)
    local head = math.exp(-(dist * dist) / (2 * LIGHT_WIDTH * LIGHT_WIDTH))
    local tail = 0
    if dist < 0 then
      tail = math.exp(-(dist * dist) / (2 * TAIL_WIDTH * TAIL_WIDTH))
    end
    local path_brightness = head + 0.4 * tail

    for j = 0, TUBE_STEPS - 1 do
      local phi = j / TUBE_STEPS * TAU
      local cphi, sphi = math.cos(phi), math.sin(phi)

      -- Punto y normal en la superficie del tubo, en espacio de mundo.
      local sx = cx + TUBE_RADIUS * (nx * cphi + bx * sphi)
      local sy = cy + TUBE_RADIUS * (ny * cphi + by * sphi)
      local sz = 0 + TUBE_RADIUS * (nz * cphi + bz * sphi)
      local normx, normy, normz = normalize(nx * cphi + bx * sphi, ny * cphi + by * sphi, nz * cphi + bz * sphi)

      -- Cámara: inclinar y alejar en Z.
      local rx, ry, rz = tilt(sx, sy, sz)
      local nrx, nry, nrz = tilt(normx, normy, normz)
      local depth = rz + CAMERA_Z

      -- Proyección en perspectiva simple al buffer de pantalla (celdas de
      -- terminal, ~2:1 alto:ancho, de ahí el *0.5 en Y).
      local px = math.floor(width / 2 + scale_x * rx / depth * 2)
      local py = math.floor(height / 2 + scale_y * ry / depth * 0.5)
      if px >= 0 and px < width and py >= 0 and py < height then
        local idx = py * width + px + 1
        local inv_depth = 1 / depth
        if inv_depth > zbuffer[idx] then
          zbuffer[idx] = inv_depth
          -- Sombreado tipo Lambert (luz de cámara fija) para que el tubo
          -- se lea como volumen, más el aporte de la luz viajera.
          local shade = math.max(0, nrx * 0.3 + nry * 0.3 + nrz * 0.9)
          local brightness = shade * 0.5 + path_brightness
          litbuffer[idx] = brightness
        end
      end
    end
  end

  for idx = 1, width * height do
    local b = litbuffer[idx]
    if b then
      screen[idx] = b > 0.85 and "1" or "0"
    end
  end

  local lines = {}
  for row = 0, height - 1 do
    local chars = {}
    for col = 1, width do
      chars[col] = screen[row * width + col]
    end
    lines[row + 1] = table.concat(chars)
  end
  return lines
end

return M
