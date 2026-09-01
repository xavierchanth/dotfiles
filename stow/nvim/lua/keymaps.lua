vim.keymap.set({ "n", "v" }, "<leader>", "")
vim.keymap.set({ "i", "n" }, "<esc>", "<cmd>noh<cr><esc>")

vim.keymap.set(
  { "n", "x" },
  "j",
  "v:count == 0 ? 'gj' : 'j'",
  { expr = true, silent = true }
)
vim.keymap.set(
  { "n", "x" },
  "k",
  "v:count == 0 ? 'gk' : 'k'",
  { expr = true, silent = true }
)

-- window maps
vim.keymap.set("n", "<leader>w", "<c-w>", { remap = true })
vim.keymap.set("n", "<leader>-", "<C-W>s", { remap = true })
vim.keymap.set("n", "<leader>\\", "<C-W>v", { remap = true })

-- Better indenting
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("v", ">", ">gv")

-- Better search
-- https://github.com/mhinz/vim-galore#saner-behavior-of-n-and-n
vim.keymap.set(
  { "n", "x", "o" },
  "n",
  "'Nn'[v:searchforward].'zv'",
  { expr = true }
)
vim.keymap.set(
  { "n", "x", "o" },
  "N",
  "'nN'[v:searchforward].'zv'",
  { expr = true }
)

-- Escape behaviors
vim.keymap.set("t", "<ESC><ESC>", "<C-\\><C-n>", { noremap = true })
vim.keymap.set("t", "<S-Space>", "<Space>", { noremap = true })

-- Undo break points
vim.keymap.set("i", ",", ",<c-g>u")
vim.keymap.set("i", ".", ".<c-g>u")
vim.keymap.set("i", ";", ";<c-g>u")

-- diagnostics
vim.keymap.set("n", "<leader>xx", "<cmd>lua vim.diagnostic.setqflist()<cr>")
vim.keymap.set("n", "<leader>xX", "<cmd>lua vim.diagnostic.setloclist()<cr>")

-- PLUGINS

-- Oil.nvim
vim.keymap.set("n", "<leader>e", "<cmd>lua require('oil').open()<cr>")

-- vim-tmux-navigator
vim.keymap.set({ "n", "t", "i" }, "<c-h>", "<cmd>TmuxNavigateLeft<cr>")
vim.keymap.set({ "n", "t", "i" }, "<c-j>", "<cmd>TmuxNavigateDown<cr>")
vim.keymap.set({ "n", "t", "i" }, "<c-k>", "<cmd>TmuxNavigateUp<cr>")
vim.keymap.set({ "n", "t", "i" }, "<c-l>", "<cmd>TmuxNavigateRight<cr>")

vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>")

-- Snacks
vim.keymap.set("n", "<leader><space>", function()
  require("snacks.picker").files({ cwd = vim.fn.getcwd() })
end)
vim.keymap.set("n", "<leader>sf", function()
  require("snacks.picker").files({
    cwd = vim.fn.getcwd(),
    hidden = true,
  })
end)
vim.keymap.set("n", "<leader>sg", function()
  require("snacks.picker").grep()
end)
vim.keymap.set("n", "<leader>sc", function()
  require("snacks.picker").resume()
end)
vim.keymap.set("n", "<leader>z", function()
  require("snacks").zen.zen({
    wo = { winhighlight = "NormalFloat:Normal" },
  })
end)
vim.keymap.set("n", "<leader>f", function()
  require("snacks").zen.zoom()
end)

-- Grug
vim.keymap.set({ "n", "v" }, "<leader>sr", function()
  local grug = require("grug-far")
  local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
  grug.open({
    transient = true,
    prefills = {
      filesFilter = ext and ext ~= "" and "*." .. ext or nil,
    },
  })
end)

-- Mini.diff
vim.keymap.set(
  "n",
  "<leader>go",
  "<cmd>lua require('mini.diff').toggle_overlay(0)<cr>"
)

-- Harpoon
vim.keymap.set("n", "<leader>j", function()
  local h = require("harpoon")
  h.ui:toggle_quick_menu(h:list("buffers"))
end)

-- cmp
vim.keymap.set("i", "<cr>", function()
  return require("utils/cmpvisible")() and "<C-y>" or "<cr>"
end, { expr = true })
