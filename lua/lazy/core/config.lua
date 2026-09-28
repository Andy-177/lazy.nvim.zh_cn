local Util = require("lazy.core.util")

---@class LazyCoreConfig
local M = {}

---@class LazyConfig
M.defaults = {
  root = vim.fn.stdpath("data") .. "/lazy", -- 插件的安装目录
  defaults = {
    -- 将此项设为 `true`，可让所有插件默认都按需加载。
    -- 只有在你清楚这样做的后果时才启用，因为它可能导致意外的行为。
    lazy = false, -- 插件是否按需加载？
    -- 目前建议保持 version=false，因为很多支持版本控制的插件
    -- 其发布版本已经过时，可能会破坏你的 Neovim 安装。
    version = nil, -- 始终使用最新的 git 提交
    -- version = "*", -- 尝试为支持 semver 的插件安装最新的稳定版本
    -- 默认的 `cond`，可用于在全局层面禁用大量插件，
    -- 例如在 vscode 中运行时禁用它们
    cond = nil, ---@type boolean|fun(self:LazyPlugin):boolean|nil
  },
  -- 当把 spec 作为 setup() 的第一个参数传入时，保持 nil
  spec = nil, ---@type LazySpec
  local_spec = true, -- 加载项目专属的 .lazy.lua spec 文件。它们会被添加到 spec 的末尾。
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json", -- 执行 update 后生成的锁定文件。
  ---@type number? 限制并发任务的最大数量
  concurrency = jit.os:find("Windows") and (vim.uv.available_parallelism() * 2) or nil,
  git = {
    -- `Lazy log` 命令的默认参数
    -- log = { "--since=3 days ago" }, -- 显示最近 3 天的提交
    log = { "-8" }, -- 显示最近 8 个提交
    timeout = 120, -- 终止运行超过 2 分钟的进程
    url_format = "https://github.com/%s.git",
    -- lazy.nvim 需要 git >=2.19.0。如果你确实想用更旧的版本来使用 lazy，
    -- 则把下面这项设为 false。这样应该能工作，但属于**不受支持**的用法，
    -- 并且会大幅增加下载量。
    filter = true,
    -- 与网络相关的 git 操作（clone、fetch、checkout）的频率限制
    throttle = {
      enabled = false, -- 默认不启用
      -- 每 5 秒最多 2 次操作
      rate = 2,
      duration = 5 * 1000, -- 单位：毫秒
    },
    -- 再次对某个插件执行 fetch 之前需要等待的秒数。
    -- 重复的 update/check 操作在这个冷却期结束前不会再次执行。
    cooldown = 0,
  },
  pkg = {
    enabled = true,
    cache = vim.fn.stdpath("state") .. "/lazy/pkg-cache.lua",
    -- 插件找到的第一个可用的包源将被使用。
    sources = {
      "lazy",
      "rockspec", -- 仅当 rocks.enabled 为 true 时才会使用
      "packspec",
    },
  },
  rocks = {
    enabled = true,
    root = vim.fn.stdpath("data") .. "/lazy-rocks",
    server = "https://lumen-oss.github.io/rocks-binaries/",
    -- 是否使用 hererocks 来安装 luarocks？
    -- 设为 `nil` 表示在找不到 luarocks 时使用 hererocks
    -- 设为 `true` 表示始终使用 hererocks
    -- 设为 `false` 表示始终使用 luarocks
    hererocks = nil,
  },
  dev = {
    -- 存放本地插件项目的目录。如果使用函数，
    -- 则必须返回插件目录（例如 `~/projects/plugin-name`）。
    ---@type string | fun(plugin: LazyPlugin): string
    path = "~/projects",
    ---@type string[] 匹配这些模式的插件将使用你的本地版本，而不是从 GitHub 拉取
    patterns = {}, -- 例如 {"folke"}
    fallback = false, -- 当本地插件不存在时回退到 git
  },
  install = {
    -- 启动时安装缺失的插件。这不会增加启动时间。
    missing = true,
    -- 启动时若要开始安装，则尝试加载其中某个配色方案
    colorscheme = { "habamax" },
  },
  ui = {
    -- 小于 1 的数字表示百分比，大于 1 表示固定尺寸
    size = { width = 0.8, height = 0.8 },
    wrap = true, -- 在界面中换行显示
    -- UI 窗口使用的边框。接受与 |nvim_open_win()| 相同的 border 取值。
    border = "none",
    -- 背景遮罩的不透明度。0 表示完全不透明，100 表示完全透明。
    backdrop = 60,
    title = nil, ---@type string 仅当 border 不为 "none" 时生效
    title_pos = "center", ---@type "center" | "left" | "right"
    -- 在 Lazy 窗口顶部显示药丸式导航按钮
    pills = true, ---@type boolean
    icons = {
      cmd = " ",
      config = "",
      debug = "● ",
      event = " ",
      favorite = " ",
      ft = " ",
      init = " ",
      import = " ",
      keys = " ",
      lazy = "󰒲 ",
      loaded = "●",
      not_loaded = "○",
      plugin = " ",
      runtime = " ",
      require = "󰢱 ",
      source = " ",
      start = " ",
      task = "✔ ",
      list = {
        "●",
        "➜",
        "★",
        "‒",
      },
    },
    -- 保持 nil，以便根据你的操作系统自动选择浏览器。
    -- 如果你想使用特定的浏览器，可以在这里定义
    browser = nil, ---@type string?
    throttle = 1000 / 30, -- 界面处理并渲染事件的频率
    custom_keys = {
      -- 你可以在这里定义自定义按键映射。如果存在，
      -- 其描述会显示在帮助菜单中。
      -- 若要禁用某个默认按键，把它设为 false。

      ["<localleader>l"] = {
        function(plugin)
          require("lazy.util").float_term({ "lazygit", "log" }, {
            cwd = plugin.dir,
          })
        end,
        desc = "打开 lazygit 日志",
      },

      ["<localleader>i"] = {
        function(plugin)
          Util.notify(vim.inspect(plugin), {
            title = "检查 " .. plugin.name,
            lang = "lua",
          })
        end,
        desc = "检查插件",
      },

      ["<localleader>t"] = {
        function(plugin)
          require("lazy.util").float_term(nil, {
            cwd = plugin.dir,
          })
        end,
        desc = "在插件目录中打开终端",
      },
    },
  },
  -- headless（无界面）模式下的输出选项
  headless = {
    -- 显示 git 等进程命令的输出
    process = true,
    -- 显示日志信息
    log = true,
    -- 显示任务的开始/结束
    task = true,
    -- 使用 ansi 颜色
    colors = true,
  },
  diff = {
    -- diff 命令 <d> 可以是以下之一：
    -- * browser：打开 github 的比较视图。请注意它总是同时绑定到 <K>，
    --   因此你可以为 diff <d> 设置不同的命令
    -- * git：运行 git diff 并打开一个 filetype 为 git 的缓冲区
    -- * terminal_git：打开一个运行 git diff 的伪终端
    -- * diffview.nvim：打开 Diffview 来显示差异
    cmd = "git",
  },
  checker = {
    -- 自动检查插件更新
    enabled = false,
    concurrency = nil, ---@type number? 设为 1 可以非常缓慢地检查更新
    notify = true, -- 发现新更新时给出通知
    frequency = 3600, -- 每小时检查一次更新
    check_pinned = false, -- 检查无法更新的已锁定（pinned）软件包
  },
  change_detection = {
    -- 自动检查配置文件变更并重新加载界面
    enabled = true,
    notify = true, -- 发现变更时给出通知
  },
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true, -- 重置包路径以加快启动速度
    rtp = {
      reset = true, -- 将运行时路径重置为 $VIMRUNTIME 和你的配置目录
      ---@type string[]
      paths = {}, -- 在这里添加任何你想包含进 rtp 的自定义路径
      ---@type string[] 在这里列出任何你想禁用的插件
      disabled_plugins = {
        -- "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        -- "tarPlugin",
        -- "tohtml",
        -- "tutor",
        -- "zipPlugin",
      },
    },
  },
  -- lazy 可以从 markdown readme 文件的标题生成 helptags，
  -- 因此即使插件没有 vim 文档，:help 也能正常工作。
  -- 用 :help 打开 readme 时，它会被正确地按 markdown 渲染
  readme = {
    enabled = true,
    root = vim.fn.stdpath("state") .. "/lazy/readme",
    files = { "README.md", "lua/**/README.md" },
    -- 只为那些没有文档的插件生成 markdown helptags
    skip_if_doc_exists = true,
  },
  state = vim.fn.stdpath("state") .. "/lazy/state.json", -- checker 等功能使用的状态信息
  -- 启用 lazy.nvim 的性能分析。这会带来一些额外开销，
  -- 因此只在你调试 lazy.nvim 时才启用
  profiling = {
    -- 在 debug 标签页中启用与 loader 缓存相关的额外统计信息。
    -- 同时还会收集所有 package.loaders 的统计数据
    loader = false,
    -- 在 Lazy 性能分析标签页中追踪每一次新的 require
    require = false,
  },
  debug = false,
}

function M.hererocks()
  if M.options.rocks.hererocks == nil then
    M.options.rocks.hererocks = vim.fn.executable("luarocks") == 0
  end
  return M.options.rocks.hererocks
end

M.version = "11.17.5" -- x-release-please-version

M.ns = vim.api.nvim_create_namespace("lazy")

---@type LazySpecLoader
M.spec = nil

---@type table<string, LazyPlugin>
M.plugins = {}

---@type LazyPlugin[]
M.to_clean = {}

---@type LazyConfig
M.options = {}

---@type string
M.me = nil

---@type string
M.mapleader = nil

---@type string
M.maplocalleader = nil

M.suspended = false

function M.headless()
  return not M.suspended and #vim.api.nvim_list_uis() == 0
end

---@param opts? LazyConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  if type(M.options.spec) == "string" then
    M.options.spec = { import = M.options.spec }
  end
  table.insert(M.options.install.colorscheme, "habamax")

  -- 根目录
  M.options.root = Util.norm(M.options.root)
  if type(M.options.dev.path) == "string" then
    M.options.dev.path = Util.norm(M.options.dev.path)
  end
  M.options.lockfile = Util.norm(M.options.lockfile)
  M.options.readme.root = Util.norm(M.options.readme.root)

  vim.fn.mkdir(M.options.root, "p")

  if M.options.performance.reset_packpath then
    vim.go.packpath = vim.env.VIMRUNTIME
  end

  M.me = debug.getinfo(1, "S").source:sub(2)
  M.me = Util.norm(vim.fn.fnamemodify(M.me, ":p:h:h:h:h"))
  local lib = vim.fn.fnamemodify(vim.v.progpath, ":p:h:h") .. "/lib"
  lib = vim.uv.fs_stat(lib .. "64") and (lib .. "64") or lib
  lib = lib .. "/nvim"
  if M.options.performance.rtp.reset then
    ---@type vim.Option
    vim.opt.rtp = {
      vim.fn.stdpath("config"),
      vim.fn.stdpath("data") .. "/site",
      M.me,
      vim.env.VIMRUNTIME,
      lib,
      vim.fn.stdpath("config") .. "/after",
    }
  end
  for _, path in ipairs(M.options.performance.rtp.paths) do
    vim.opt.rtp:append(path)
  end
  vim.opt.rtp:append(M.options.readme.root)

  -- 禁用插件自动加载，因为我们自己完成了所有这些工作
  vim.go.loadplugins = false
  M.mapleader = vim.g.mapleader
  M.maplocalleader = vim.g.maplocalleader

  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      require("lazy.stats").on_ui_enter()
    end,
  })

  if M.headless() then
    require("lazy.view.commands").setup()
  else
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        require("lazy.view.commands").setup()
        if M.options.change_detection.enabled then
          require("lazy.manage.reloader").enable()
        end
        if M.options.checker.enabled then
          vim.defer_fn(function()
            require("lazy.manage.checker").start()
          end, 10)
        end

        -- 当插件开发者修改 packspec 文件时很有用
        vim.api.nvim_create_autocmd("BufWritePost", {
          pattern = { "lazy.lua", "pkg.json", "*.rockspec" },
          callback = function()
            local plugin = require("lazy.core.plugin").find(vim.uv.cwd() .. "/lua/")
            if plugin then
              require("lazy").pkg({ plugins = { plugin } })
            end
          end,
        })

        vim.api.nvim_create_autocmd({ "VimSuspend", "VimResume" }, {
          callback = function(ev)
            M.suspended = ev.event == "VimSuspend"
          end,
        })
      end,
    })
  end

  Util.very_lazy()
end

return M
