local qr = require("qrencode.qr")
local ui = require("qrencode.ui")

local M = {}

local defaults = {
  ecl = "M",
  border = 4,
}

M.config = vim.deepcopy(defaults)

local function read_buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function read_visual_text(buf)
  local mode = vim.fn.visualmode()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local sr = start_pos[2] - 1
  local er = end_pos[2] - 1

  if sr > er or (sr == er and start_pos[3] > end_pos[3]) then
    start_pos, end_pos = end_pos, start_pos
    sr = start_pos[2] - 1
    er = end_pos[2] - 1
  end

  local sc = start_pos[3] - 1
  local ec = end_pos[3]

  if mode == "V" then
    return table.concat(vim.api.nvim_buf_get_lines(buf, sr, er + 1, false), "\n")
  end

  if mode == "\022" then
    local left = math.min(start_pos[3], end_pos[3]) - 1
    local right = math.max(start_pos[3], end_pos[3])
    local parts = {}
    for row = sr, er do
      local chunk = vim.api.nvim_buf_get_text(buf, row, left, row, right, {})
      parts[#parts + 1] = table.concat(chunk, "")
    end
    return table.concat(parts, "\n")
  end

  local parts = vim.api.nvim_buf_get_text(buf, sr, sc, er, ec, {})
  return table.concat(parts, "\n")
end

local function encode_and_show(text)
  local cleaned = text:gsub("^%s+", ""):gsub("%s+$", "")
  if cleaned == "" then
    vim.notify("qrencode.nvim: nothing to encode", vim.log.levels.WARN)
    return
  end

  local ok, result = pcall(qr.encode, cleaned, { ecl = M.config.ecl })
  if not ok then
    vim.notify("qrencode.nvim: " .. result, vim.log.levels.ERROR)
    return
  end

  ui.show(result.modules, {
    border = M.config.border,
  })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.config
end

function M.buffer()
  encode_and_show(read_buffer_text(0))
end

function M.selection()
  encode_and_show(read_visual_text(0))
end

function M.show(text)
  encode_and_show(text)
end

function M.close()
  ui.close()
end

return M
