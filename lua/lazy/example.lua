return {
  -- 启动 Neovim 时，配色方案就应该已经可用
  {
    "folke/tokyonight.nvim",
    lazy = false, -- 确保在启动时就加载它，如果它是你主要使用的配色方案
    priority = 1000, -- 确保在所有其他启动插件之前加载
    config = function()
      -- 在这里加载配色方案
      vim.cmd([[colorscheme tokyonight]])
    end,
  },

  -- 我有一个单独的 config.mappings 文件，里面 require 了 which-key。
  -- 有了 lazy，插件会在某处被 require 时自动加载
  { "folke/which-key.nvim", lazy = true },

  {
    "nvim-neorg/neorg",
    -- 按文件类型延迟加载
    ft = "norg",
    -- neorg 的选项。这会自动调用 `require("neorg").setup(opts)`
    opts = {
      load = {
        ["core.defaults"] = {},
      },
    },
  },

  {
    "dstein64/vim-startuptime",
    -- 按命令延迟加载
    cmd = "StartupTime",
    -- init 会在启动期间被调用。vim 插件的配置通常应该放在 init 函数中设置
    init = function()
      vim.g.startuptime_tries = 10
    end,
  },

  {
    "hrsh7th/nvim-cmp",
    -- 在 InsertEnter 时加载 cmp
    event = "InsertEnter",
    -- 这些依赖只有在 cmp 加载时才会被加载
    -- 除非另有说明，依赖总是延迟加载的
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
    },
    config = function()
      -- ...
    end,
  },

  -- 如果某些代码 require 了某个未加载插件中的模块，该插件会被自动加载。
  -- 所以对于像 devicons 这样的 api 插件，我们总可以设置 lazy=true
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- 对于可以稍后加载、且对初始 UI 不重要的事情，
  -- 你可以使用 VeryLazy 事件
  { "stevearc/dressing.nvim", event = "VeryLazy" },

  {
    "Wansmer/treesj",
    keys = {
      { "J", "<cmd>TSJToggle<cr>", desc = "切换合并" },
    },
    opts = { use_default_keymaps = false, max_join_length = 150 },
  },

  {
    "monaqa/dial.nvim",
    -- 按按键延迟加载
    -- mode 默认为 `n`。想了解更高级的选项，请参阅快捷键映射一节
    keys = { "<C-a>", { "<C-x>", mode = "n" } },
  },

  -- 本地插件需要用 dir 显式配置
  { dir = "~/projects/secret.nvim" },

  -- 你可以用自定义 url 来获取一个插件
  { url = "git@github.com:folke/noice.nvim.git" },

  -- 本地插件也可以用 dev 选项来配置。
  -- 这会使用 {config.dev.path}/noice.nvim/，而不是从 GitHub 获取
  -- 使用 dev 选项时，你可以轻松地在插件的本地版本和已安装版本之间切换
  { "folke/noice.nvim", dev = true },
}
