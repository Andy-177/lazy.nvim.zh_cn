#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"

vim.opt.rtp:prepend(".")

-- 初始化 lazy.nvim
require("lazy.minit").setup({
  spec = {
    { dir = vim.uv.cwd() },
  },
})
