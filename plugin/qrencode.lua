if vim.g.loaded_qrencode_nvim == 1 then
  return
end
vim.g.loaded_qrencode_nvim = 1

vim.api.nvim_create_user_command("QREncodeBuffer", function()
  require("qrencode").buffer()
end, {
  desc = "Generate a QR code from the current buffer",
})

vim.api.nvim_create_user_command("QREncodeSelection", function()
  require("qrencode").selection()
end, {
  range = true,
  desc = "Generate a QR code from the current visual selection",
})

vim.api.nvim_create_user_command("QREncodeClose", function()
  require("qrencode").close()
end, {
  desc = "Close the QR code preview window",
})
