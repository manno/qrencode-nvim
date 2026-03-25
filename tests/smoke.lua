local qr = require("qrencode.qr")
local plugin = require("qrencode")

local result = qr.encode("https://github.com/neovim/neovim", { ecl = "M" })
assert(result.version >= 1)
assert(result.size == result.version * 4 + 17)
assert(type(result.modules[1][1]) == "boolean")

plugin.show("https://github.com/neovim/neovim")
plugin.close()
print("qrencode-nvim smoke ok")
