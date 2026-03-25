local M = {}

local state = {
  buf = nil,
  win = nil,
}

local function max_width(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.api.nvim_strwidth(line))
  end
  return width
end

local function close_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
  state.buf = nil
end

local function apply_close_maps(buf)
  local function close()
    require("qrencode").close()
  end
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true, nowait = true })
end

local function create_float(width, height, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    row = row,
    col = col,
    width = width,
    height = height,
    noautocmd = true,
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false
  vim.wo[win].spell = false

  apply_close_maps(buf)
  state.buf = buf
  state.win = win
  return buf, win
end

local function render_text_lines(modules, border)
  border = border or 4
  local size = #modules
  local total = size + border * 2
  local lines = {}

  local function at(y, x)
    local yy = y - border
    local xx = x - border
    if yy < 1 or yy > size or xx < 1 or xx > size then
      return false
    end
    return modules[yy][xx]
  end

  for y = 1, total, 2 do
    local line = {}
    for x = 1, total do
      local top = at(y, x)
      local bottom = at(y + 1, x)
      if top and bottom then
        line[#line + 1] = "█"
      elseif top then
        line[#line + 1] = "▀"
      elseif bottom then
        line[#line + 1] = "▄"
      else
        line[#line + 1] = " "
      end
    end
    lines[#lines + 1] = table.concat(line)
  end

  return lines
end

local function show_text(modules, config)
  local lines = render_text_lines(modules, config.border)
  local width = math.min(max_width(lines), vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  local buf = create_float(width, height, " QR Code ")
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.show(modules, config)
  close_window()
  show_text(modules, config)
end

function M.close()
  close_window()
end

return M
