local conform = require("conform")
conform.setup({
  format_on_save = function(bufnr)
    if not vim.g.autoformat then
      return
    end
    return { buf = bufnr }
  end,
  default_format_opts = {
    timeout_ms = 3000,
    async = false,
    quiet = false,
  },
  formatters_by_ft = {
    cmake = { "gersemi" },
    cs = { "csharpier" },
    go = { "goimports", "gofumpt" },
    lua = { "stylua" },
    quarto = { "injected" },
    sh = { "shfmt" },
    zig = { "zigfmt" },
    zsh = { "shfmt" },
    -- typescript = { "prettier" },
    -- javascript = { "prettier" },
    -- svelte = { "prettier" },
    -- html = { "prettier" },
    -- css = { "prettier" },
  },
  formatters = {
    csharpier = {
      command = "dotnet-csharpier",
      args = { "--write-stdout" },
    },
    gersemi = { prepend_args = { "--indent", "2" } }, -- cmake formatter
    injected = {
      options = {
        ignore_errors = false,
        lang_to_ext = {
          bash = "sh",
          c_sharp = "cs",
          elixir = "exs",
          javascript = "js",
          julia = "jl",
          latex = "tex",
          markdown = "md",
          python = "py",
          ruby = "rb",
          rust = "rs",
          teal = "tl",
          r = "r",
          typescript = "ts",
        },
        lang_to_formatters = {},
      },
    },
    prettier = { prepend_args = { "--prose-wrap", "always" } },
  },
})
