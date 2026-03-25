-- Adapted in part from Project Nayuki's QR Code generator library (MIT License).
-- Original source: https://www.nayuki.io/page/qr-code-generator-library
-- Copyright (c) Project Nayuki.

local ok, bit = pcall(require, "bit")
if not ok then
  bit = bit32
end

local M = {}

local ECC_CODEWORDS_PER_BLOCK = {
  L = { 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
  M = { 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 },
  Q = { 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
  H = { 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
}

local NUM_ERROR_CORRECTION_BLOCKS = {
  L = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 },
  M = { 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 },
  Q = { 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 },
  H = { 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 },
}

local FORMAT_BITS = {
  L = 1,
  M = 0,
  Q = 3,
  H = 2,
}

local PENALTY_N1 = 3
local PENALTY_N2 = 3
local PENALTY_N3 = 40
local PENALTY_N4 = 10

local function new_matrix(size, value)
  local rows = {}
  for y = 1, size do
    local row = {}
    for x = 1, size do
      row[x] = value
    end
    rows[y] = row
  end
  return rows
end

local function set_module(matrix, x, y, value)
  matrix[y + 1][x + 1] = value
end

local function get_module(matrix, x, y)
  return matrix[y + 1][x + 1]
end

local function append_bits(value, bit_len, buffer)
  if bit_len < 0 or bit_len > 31 then
    error("bit length out of range")
  end
  for i = bit_len - 1, 0, -1 do
    buffer[#buffer + 1] = math.floor(value / (2 ^ i)) % 2
  end
end

local function to_utf8_bytes(text)
  local bytes = { string.byte(text, 1, #text) }
  return bytes
end

local function get_num_raw_data_modules(version)
  local result = (16 * version + 128) * version + 64
  if version >= 2 then
    local num_align = math.floor(version / 7) + 2
    result = result - ((25 * num_align - 10) * num_align - 55)
    if version >= 7 then
      result = result - 36
    end
  end
  return result
end

local function get_num_data_codewords(version, ecl)
  return math.floor(get_num_raw_data_modules(version) / 8)
    - ECC_CODEWORDS_PER_BLOCK[ecl][version] * NUM_ERROR_CORRECTION_BLOCKS[ecl][version]
end

local function get_alignment_pattern_positions(version, size)
  if version == 1 then
    return {}
  end
  local num_align = math.floor(version / 7) + 2
  local step = math.floor((version * 8 + num_align * 3 + 5) / (num_align * 4 - 4)) * 2
  local result = { 6 }
  local pos = size - 7
  while #result < num_align do
    table.insert(result, 2, pos)
    pos = pos - step
  end
  return result
end

local function reed_solomon_multiply(x, y)
  local z = 0
  for i = 7, 0, -1 do
    z = z * 2
    if z >= 256 then
      z = bit.bxor(z, 0x11D)
    end
    if math.floor(y / (2 ^ i)) % 2 ~= 0 then
      z = bit.bxor(z, x)
    end
  end
  return z
end

local function reed_solomon_compute_divisor(degree)
  local result = {}
  for i = 1, degree - 1 do
    result[i] = 0
  end
  result[degree] = 1

  local root = 1
  for _ = 1, degree do
    for j = 1, #result do
      result[j] = reed_solomon_multiply(result[j], root)
      if j < #result then
        result[j] = bit.bxor(result[j], result[j + 1])
      end
    end
    root = reed_solomon_multiply(root, 0x02)
  end
  return result
end

local function reed_solomon_compute_remainder(data, divisor)
  local result = {}
  for i = 1, #divisor do
    result[i] = 0
  end

  for _, byte in ipairs(data) do
    local factor = bit.bxor(byte, table.remove(result, 1))
    result[#result + 1] = 0
    for i, coef in ipairs(divisor) do
      result[i] = bit.bxor(result[i], reed_solomon_multiply(coef, factor))
    end
  end

  return result
end

local QrCode = {}
QrCode.__index = QrCode

function QrCode:new(version, ecl, data_codewords)
  local size = version * 4 + 17
  local obj = setmetatable({
    version = version,
    ecl = ecl,
    size = size,
    modules = new_matrix(size, false),
    is_function = new_matrix(size, false),
  }, self)

  obj:draw_function_patterns()
  local all_codewords = obj:add_ecc_and_interleave(data_codewords)
  obj:draw_codewords(all_codewords)

  local best_mask = 0
  local min_penalty = math.huge
  for mask = 0, 7 do
    obj:apply_mask(mask)
    obj:draw_format_bits(mask)
    local penalty = obj:get_penalty_score()
    if penalty < min_penalty then
      min_penalty = penalty
      best_mask = mask
    end
    obj:apply_mask(mask)
  end

  obj.mask = best_mask
  obj:apply_mask(best_mask)
  obj:draw_format_bits(best_mask)
  obj.is_function = nil
  return obj
end

function QrCode:set_function_module(x, y, is_dark)
  set_module(self.modules, x, y, is_dark)
  set_module(self.is_function, x, y, true)
end

function QrCode:draw_finder_pattern(x, y)
  for dy = -4, 4 do
    for dx = -4, 4 do
      local dist = math.max(math.abs(dx), math.abs(dy))
      local xx = x + dx
      local yy = y + dy
      if 0 <= xx and xx < self.size and 0 <= yy and yy < self.size then
        self:set_function_module(xx, yy, dist ~= 2 and dist ~= 4)
      end
    end
  end
end

function QrCode:draw_alignment_pattern(x, y)
  for dy = -2, 2 do
    for dx = -2, 2 do
      self:set_function_module(x + dx, y + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
    end
  end
end

function QrCode:draw_format_bits(mask)
  local data = bit.bor(bit.lshift(FORMAT_BITS[self.ecl], 3), mask)
  local rem = data
  for _ = 1, 10 do
    rem = bit.bxor(bit.lshift(rem, 1), bit.band(bit.rshift(rem, 9), 1) * 0x537)
  end
  local bits = bit.bxor(bit.bor(bit.lshift(data, 10), rem), 0x5412)

  for i = 0, 5 do
    self:set_function_module(8, i, bit.band(bit.rshift(bits, i), 1) ~= 0)
  end
  self:set_function_module(8, 7, bit.band(bit.rshift(bits, 6), 1) ~= 0)
  self:set_function_module(8, 8, bit.band(bit.rshift(bits, 7), 1) ~= 0)
  self:set_function_module(7, 8, bit.band(bit.rshift(bits, 8), 1) ~= 0)
  for i = 9, 14 do
    self:set_function_module(14 - i, 8, bit.band(bit.rshift(bits, i), 1) ~= 0)
  end

  for i = 0, 7 do
    self:set_function_module(self.size - 1 - i, 8, bit.band(bit.rshift(bits, i), 1) ~= 0)
  end
  for i = 8, 14 do
    self:set_function_module(8, self.size - 15 + i, bit.band(bit.rshift(bits, i), 1) ~= 0)
  end
  self:set_function_module(8, self.size - 8, true)
end

function QrCode:draw_version()
  if self.version < 7 then
    return
  end

  local rem = self.version
  for _ = 1, 12 do
    rem = bit.bxor(bit.lshift(rem, 1), bit.band(bit.rshift(rem, 11), 1) * 0x1F25)
  end
  local bits = bit.bor(bit.lshift(self.version, 12), rem)

  for i = 0, 17 do
    local color = bit.band(bit.rshift(bits, i), 1) ~= 0
    local a = self.size - 11 + (i % 3)
    local b = math.floor(i / 3)
    self:set_function_module(a, b, color)
    self:set_function_module(b, a, color)
  end
end

function QrCode:draw_function_patterns()
  for i = 0, self.size - 1 do
    self:set_function_module(6, i, i % 2 == 0)
    self:set_function_module(i, 6, i % 2 == 0)
  end

  self:draw_finder_pattern(3, 3)
  self:draw_finder_pattern(self.size - 4, 3)
  self:draw_finder_pattern(3, self.size - 4)

  local positions = get_alignment_pattern_positions(self.version, self.size)
  local count = #positions
  for i = 1, count do
    for j = 1, count do
      if not ((i == 1 and j == 1) or (i == 1 and j == count) or (i == count and j == 1)) then
        self:draw_alignment_pattern(positions[i], positions[j])
      end
    end
  end

  self:draw_format_bits(0)
  self:draw_version()
end

function QrCode:add_ecc_and_interleave(data)
  local num_blocks = NUM_ERROR_CORRECTION_BLOCKS[self.ecl][self.version]
  local block_ecc_len = ECC_CODEWORDS_PER_BLOCK[self.ecl][self.version]
  local raw_codewords = math.floor(get_num_raw_data_modules(self.version) / 8)
  local num_short_blocks = num_blocks - (raw_codewords % num_blocks)
  local short_block_len = math.floor(raw_codewords / num_blocks)

  local blocks = {}
  local divisor = reed_solomon_compute_divisor(block_ecc_len)
  local k = 1

  for i = 0, num_blocks - 1 do
    local data_len = short_block_len - block_ecc_len + ((i < num_short_blocks) and 0 or 1)
    local dat = {}
    for j = 1, data_len do
      dat[j] = data[k]
      k = k + 1
    end
    local ecc = reed_solomon_compute_remainder(dat, divisor)
    if i < num_short_blocks then
      dat[#dat + 1] = 0
    end
    for _, v in ipairs(ecc) do
      dat[#dat + 1] = v
    end
    blocks[#blocks + 1] = dat
  end

  local result = {}
  for i = 1, #blocks[1] do
    for j = 1, #blocks do
      if not (i == short_block_len - block_ecc_len + 1 and j <= num_short_blocks) then
        result[#result + 1] = blocks[j][i]
      end
    end
  end
  return result
end

function QrCode:draw_codewords(data)
  local bit_index = 0
  local total_bits = #data * 8

  local right = self.size - 1
  while right >= 1 do
    if right == 6 then
      right = 5
    end
    for vert = 0, self.size - 1 do
      for j = 0, 1 do
        local x = right - j
        local upward = bit.band(right + 1, 2) == 0
        local y = upward and (self.size - 1 - vert) or vert
        if not get_module(self.is_function, x, y) and bit_index < total_bits then
          local byte = data[math.floor(bit_index / 8) + 1]
          local bit_pos = 7 - (bit_index % 8)
          set_module(self.modules, x, y, bit.band(bit.rshift(byte, bit_pos), 1) ~= 0)
          bit_index = bit_index + 1
        end
      end
    end
    right = right - 2
  end
end

function QrCode:apply_mask(mask)
  for y = 0, self.size - 1 do
    for x = 0, self.size - 1 do
      local invert
      if mask == 0 then
        invert = (x + y) % 2 == 0
      elseif mask == 1 then
        invert = y % 2 == 0
      elseif mask == 2 then
        invert = x % 3 == 0
      elseif mask == 3 then
        invert = (x + y) % 3 == 0
      elseif mask == 4 then
        invert = (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0
      elseif mask == 5 then
        invert = (x * y) % 2 + (x * y) % 3 == 0
      elseif mask == 6 then
        invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
      else
        invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
      end
      if not get_module(self.is_function, x, y) and invert then
        set_module(self.modules, x, y, not get_module(self.modules, x, y))
      end
    end
  end
end

function QrCode:finder_penalty_add_history(current_run_length, history)
  if history[1] == 0 then
    current_run_length = current_run_length + self.size
  end
  for i = #history, 2, -1 do
    history[i] = history[i - 1]
  end
  history[1] = current_run_length
end

function QrCode:finder_penalty_count_patterns(history)
  local n = history[2]
  local core = n > 0
    and history[3] == n
    and history[4] == n * 3
    and history[5] == n
    and history[6] == n

  local result = 0
  if core and history[1] >= n * 4 and history[7] >= n then
    result = result + 1
  end
  if core and history[7] >= n * 4 and history[1] >= n then
    result = result + 1
  end
  return result
end

function QrCode:finder_penalty_terminate_and_count(current_run_color, current_run_length, history)
  if current_run_color then
    self:finder_penalty_add_history(current_run_length, history)
    current_run_length = 0
  end
  current_run_length = current_run_length + self.size
  self:finder_penalty_add_history(current_run_length, history)
  return self:finder_penalty_count_patterns(history)
end

function QrCode:get_penalty_score()
  local result = 0

  for y = 1, self.size do
    local run_color = false
    local run_x = 0
    local history = { 0, 0, 0, 0, 0, 0, 0 }
    for x = 1, self.size do
      local color = self.modules[y][x]
      if color == run_color then
        run_x = run_x + 1
        if run_x == 5 then
          result = result + PENALTY_N1
        elseif run_x > 5 then
          result = result + 1
        end
      else
        self:finder_penalty_add_history(run_x, history)
        if not run_color then
          result = result + self:finder_penalty_count_patterns(history) * PENALTY_N3
        end
        run_color = color
        run_x = 1
      end
    end
    result = result + self:finder_penalty_terminate_and_count(run_color, run_x, history) * PENALTY_N3
  end

  for x = 1, self.size do
    local run_color = false
    local run_y = 0
    local history = { 0, 0, 0, 0, 0, 0, 0 }
    for y = 1, self.size do
      local color = self.modules[y][x]
      if color == run_color then
        run_y = run_y + 1
        if run_y == 5 then
          result = result + PENALTY_N1
        elseif run_y > 5 then
          result = result + 1
        end
      else
        self:finder_penalty_add_history(run_y, history)
        if not run_color then
          result = result + self:finder_penalty_count_patterns(history) * PENALTY_N3
        end
        run_color = color
        run_y = 1
      end
    end
    result = result + self:finder_penalty_terminate_and_count(run_color, run_y, history) * PENALTY_N3
  end

  for y = 1, self.size - 1 do
    for x = 1, self.size - 1 do
      local color = self.modules[y][x]
      if color == self.modules[y][x + 1]
        and color == self.modules[y + 1][x]
        and color == self.modules[y + 1][x + 1]
      then
        result = result + PENALTY_N2
      end
    end
  end

  local dark = 0
  for y = 1, self.size do
    for x = 1, self.size do
      if self.modules[y][x] then
        dark = dark + 1
      end
    end
  end
  local total = self.size * self.size
  local k = math.ceil(math.abs(dark * 20 - total * 10) / total) - 1
  result = result + k * PENALTY_N4

  return result
end

local function encode_data(text, ecl)
  local bytes = to_utf8_bytes(text)
  if #bytes == 0 then
    error("cannot encode empty text")
  end

  local version
  local capacity_bits
  for ver = 1, 40 do
    local char_count_bits = ver <= 9 and 8 or 16
    local used_bits = 4 + char_count_bits + #bytes * 8
    local data_capacity_bits = get_num_data_codewords(ver, ecl) * 8
    if used_bits <= data_capacity_bits then
      version = ver
      capacity_bits = data_capacity_bits
      break
    end
  end

  if not version then
    error(string.format("text is too long for QR error correction level %s", ecl))
  end

  local bit_buffer = {}
  append_bits(0x4, 4, bit_buffer)
  append_bits(#bytes, version <= 9 and 8 or 16, bit_buffer)
  for _, byte in ipairs(bytes) do
    append_bits(byte, 8, bit_buffer)
  end

  append_bits(0, math.min(4, capacity_bits - #bit_buffer), bit_buffer)
  append_bits(0, (8 - (#bit_buffer % 8)) % 8, bit_buffer)

  local pad_byte = 0xEC
  while #bit_buffer < capacity_bits do
    append_bits(pad_byte, 8, bit_buffer)
    if pad_byte == 0xEC then
      pad_byte = 0x11
    else
      pad_byte = 0xEC
    end
  end

  local data_codewords = {}
  for i = 1, #bit_buffer, 8 do
    local value = 0
    for j = 0, 7 do
      value = value * 2 + bit_buffer[i + j]
    end
    data_codewords[#data_codewords + 1] = value
  end

  return QrCode:new(version, ecl, data_codewords)
end

function M.encode(text, opts)
  opts = opts or {}
  local ecl = string.upper(opts.ecl or "M")
  if not ECC_CODEWORDS_PER_BLOCK[ecl] then
    error(string.format("unsupported QR error correction level: %s", tostring(opts.ecl)))
  end

  local qr = encode_data(text, ecl)
  return {
    text = text,
    size = qr.size,
    version = qr.version,
    mask = qr.mask,
    ecl = ecl,
    modules = qr.modules,
  }
end

return M
