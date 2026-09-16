local cmp = require("blink-cmp")
cmp.setup({
  enabled = function()
    return not vim.tbl_contains({ "AgenticInput" }, vim.bo.filetype)
  end,
  completion = {
    list = { selection = { auto_insert = true, preselect = false } },
    menu = {
      auto_show = function(ctx)
        return ctx.mode ~= "cmdline"
      end,
    },
  },
  sources = {
    default = { "path", "snippets", "buffer" },
  },
  appearance = {
    kind_icons = {
      Copilot = "",
    },
  },
  signature = {
    window = {
      show_documentation = false,
    },
  },
  keymap = {
    preset = "default",
    ["<Esc>"] = {
      function()
        -- if require("blink.cmp").snippet_active() then
        --   vim.snippet.stop()
        -- end
        require("blink.cmp").hide()
        if vim.fn.getcmdtype() ~= "" then
          -- replace <Esc> with <C-c> if it's the command line, otherwise the command is submitted
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<C-c>", true, true, true),
            "n",
            true
          )
          return true
        end
        return false -- call fallback
      end,
      "fallback",
    },
    ["<CR>"] = { "accept", "fallback" },
    ["<C-n>"] = { "show", "select_next", "fallback" },
    ["<C-p>"] = { "show", "select_prev", "fallback" },
    ["<C-u>"] = { "scroll_documentation_up", "fallback" },
    ["<C-d>"] = { "scroll_documentation_down", "fallback" },
  },
})
