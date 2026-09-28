
---@alias LazyPluginKind "normal"|"clean"|"disabled"

---@class LazyPluginState
---@field cache? table<string,any>
---@field cloned? boolean
---@field cond? boolean
---@field dep? boolean 如果该插件仅作为依赖出现在 spec 中则为 true
---@field dir? string 为该插件显式设置的 dir 或 dev
---@field dirty? boolean
---@field build? boolean
---@field frags? number[]
---@field top? boolean
---@field handlers? LazyPluginHandlers
---@field installed? boolean
---@field is_local? boolean
---@field kind? LazyPluginKind
---@field loaded? {[string]:string}|{time:number}
---@field outdated? boolean
---@field rtp_loaded? boolean
---@field tasks? LazyTask[]
---@field updated? {from:string, to:string}
---@field updates? {from:GitInfo, to:GitInfo}
---@field last_check? number
---@field working? boolean
---@field pkg? LazyPkg

---@alias PluginOpts table|fun(self:LazyPlugin, opts:table):table?

---@class LazyPluginHooks
---@field init? fun(self:LazyPlugin) 始终会运行
---@field deactivate? fun(self:LazyPlugin) 卸载/停止插件
---@field config? fun(self:LazyPlugin, opts:table)|true 加载插件时执行
---@field build? false|string|async fun(self:LazyPlugin)|(string|async fun(self:LazyPlugin))[]
---@field opts? PluginOpts

---@class LazyPluginHandlers
---@field event? table<string,LazyEvent>
---@field ft? table<string,LazyEvent>
---@field keys? table<string,LazyKeys>
---@field cmd? table<string,string>

---@class LazyPluginRef
---@field branch? string
---@field tag? string
---@field commit? string
---@field version? string|boolean
---@field pin? boolean
---@field submodules? boolean 默认为 true

---@class LazyPluginBase
---@field [1] string?
---@field name string 显示名称，同时用作插件配置文件名
---@field main? string 包含 setup 和 deactivate 的入口模块
---@field url string?
---@field dir string
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun():boolean)
---@field optional? boolean 若设置，则除非在其他地方被添加，否则不会添加该插件
---@field lazy? boolean
---@field priority? number 仅对 lazy=false 的插件有用，用于强制优先加载某些插件。默认优先级为 50
---@field dev? boolean 若设置，则链接到 ~/projects 下的对应目录
---@field rocks? string[]
---@field virtual? boolean 虚拟插件不会被安装，也不会加入 rtp

---@class LazyPlugin: LazyPluginBase,LazyPluginHandlers,LazyPluginHooks,LazyPluginRef
---@field dependencies? string[]
---@field specs? string|string[]|LazyPluginSpec[]
---@field _ LazyPluginState

---@class LazyPluginSpecHandlers
---@field event? string[]|string|LazyEventSpec[]|fun(self:LazyPlugin, event:string[]):string[]
---@field cmd? string[]|string|fun(self:LazyPlugin, cmd:string[]):string[]
---@field ft? string[]|string|fun(self:LazyPlugin, ft:string[]):string[]
---@field keys? string|string[]|LazyKeysSpec[]|fun(self:LazyPlugin, keys:string[]):((string|LazyKeys)[])
---@field module? false

---@class LazyPluginSpec: LazyPluginBase,LazyPluginSpecHandlers,LazyPluginHooks,LazyPluginRef
---@field name? string 显示名称，同时用作插件配置文件名
---@field dir? string
---@field dependencies? string|string[]|LazyPluginSpec[]
---@field specs? string|string[]|LazyPluginSpec[]

---@alias LazySpec string|LazyPluginSpec|LazySpecImport|LazySpec[]

---@class LazySpecImport
---@field import string|(fun():LazyPluginSpec) 要导入的 spec 模块
---@field name? string
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun():boolean)

---@class LazyFragment
---@field id number
---@field pkg? boolean
---@field pid? number
---@field deps? number[]
---@field frags? number[]
---@field dep? boolean
---@field name string
---@field url? string
---@field dir? string
---@field spec LazyPlugin
