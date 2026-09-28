<h4 align="center">
  <a href="https://lazy.folke.io/installation">安装</a>
  ·
  <a href="https://lazy.folke.io/configuration">配置</a>
  ·
  <a href="https://lazy.folke.io">文档</a>
</h4>

<div align="center"><p>
    <a href="https://github.com/folke/lazy.nvim/releases/latest">
      <img alt="最新版本" src="https://img.shields.io/github/v/release/folke/lazy.nvim?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=D9E0EE&labelColor=302D41&include_prerelease&sort=semver" />
    </a>
    <a href="https://github.com/folke/lazy.nvim/pulse">
      <img alt="最近一次提交" src="https://img.shields.io/github/last-commit/folke/lazy.nvim?style=for-the-badge&logo=starship&color=8bd5ca&logoColor=D9E0EE&labelColor=302D41"/>
    </a>
    <a href="https://github.com/folke/lazy.nvim/blob/main/LICENSE">
      <img alt="许可证" src="https://img.shields.io/github/license/folke/lazy.nvim?style=for-the-badge&logo=starship&color=ee999f&logoColor=D9E0EE&labelColor=302D41" />
    </a>
    <a href="https://github.com/folke/lazy.nvim/stargazers">
      <img alt="Star 数量" src="https://img.shields.io/github/stars/folke/lazy.nvim?style=for-the-badge&logo=starship&color=c69ff5&logoColor=D9E0EE&labelColor=302D41" />
    </a>
    <a href="https://github.com/folke/lazy.nvim/issues">
      <img alt="问题" src="https://img.shields.io/github/issues/folke/lazy.nvim?style=for-the-badge&logo=bilibili&color=F5E0DC&logoColor=D9E0EE&labelColor=302D41" />
    </a>
    <a href="https://github.com/folke/lazy.nvim">
      <img alt="仓库大小" src="https://img.shields.io/github/repo-size/folke/lazy.nvim?color=%23DDB6F2&label=SIZE&logo=codesandbox&style=for-the-badge&logoColor=D9E0EE&labelColor=302D41" />
    </a>
    <a href="https://twitter.com/intent/follow?screen_name=folke">
      <img alt="在 Twitter 上关注" src="https://img.shields.io/twitter/follow/folke?style=for-the-badge&logo=twitter&color=8aadf3&logoColor=D9E0EE&labelColor=302D41" />
    </a>
</div>



**lazy.nvim** 是一个用于 Neovim 的现代化插件管理器。

![image](https://user-images.githubusercontent.com/292349/208301737-68fb279c-ba70-43ef-a369-8c3e8367d6b1.png)

## ✨ 特性

- 📦 用强大的 UI 管理你所有的 Neovim 插件
- 🚀 借助自动缓存以及 Lua 模块的字节码编译，获得极快的启动速度
- 💾 使用部分克隆（partial clone）而非浅克隆
- 🔌 自动延迟加载 Lua 模块，并支持按事件、命令、文件类型和快捷键映射延迟加载
- ⏳ 在启动 Neovim 之前自动安装缺失的插件，让你能够立刻开始使用
- 💪 异步执行以提升性能
- 🛠️ 无需手动编译插件
- 🧪 正确处理依赖关系的执行顺序
- 📁 可在多个文件中进行配置
- 📚 为没有 vimdoc 的插件，根据其 `README.md` 文件中的标题生成 helptags
- 💻 用于使用本地插件的 dev 选项与模式匹配
- 📊 用于优化性能的性能分析工具
- 🔒 锁文件 `lazy-lock.json`，用于记录已安装的插件
- 🔎 自动检查更新
- 📋 支持 commit、branch、tag、version 以及完整的 [Semver](https://devhints.io/semver)
- 📈 状态栏组件，用于显示待处理更新的数量
- 🎨 自动延迟加载配色方案

## ⚡️ 环境要求

- Neovim >= **0.8.0**（必须使用 **LuaJIT** 构建）
- Git >= **2.19.0**（用于支持部分克隆）
- 一个 [Nerd Font](https://www.nerdfonts.com/) 字体 **（可选）**
- [luarocks](https://luarocks.org/)，用于安装 rockspec。
  你可以从 `opts.pkg.sources` 中移除 `rockspec` 来禁用此功能。

## 🚀 快速上手

请查看[文档网站](https://lazy.folke.io/)以了解更多信息。