P = function(...)
  vim.print(vim.inspect(...))
end


vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Disable built-in plugins
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_tutor_mode_plugin = 1

require("options")
require("ft")
require("keymaps")

local pack = require("utils.pack")
local spec = require("assets.pack-spec")

pack.load(spec.init)

vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local kind = ev.data.kind
    if kind == "install" or kind == "update" then
      local build = ev.data.spec.data.build
      if build and type(build) == "function" then
        build(ev)
      end
    end
  end,
})

for ft, ft_spec in pairs(spec.ft) do
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    callback = function(ev)
      local cft = vim.api.nvim_get_option_value("ft", { buf = ev.buf })
      if ft == cft then
        pack.load(ft_spec)
        vim.api.nvim_del_autocmd(ev.id)
        vim.g.last_loaded_ft = ft
      end
    end,
  })
end

vim.api.nvim_create_autocmd("UIEnter", {
  command = "colorscheme clarity-cterm",
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    pack.load(spec.lazy)
  end,
})
