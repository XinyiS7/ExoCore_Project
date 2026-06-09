# ExoCore 定时开机 + 自动启动服务 配置指南

这份文档把"PC 定时开机 → Windows 自动登录 → Docker Desktop 自启 → pgvector + ExoCore 容器自启"整条链路拆成 5 步，按顺序做完即可。

---

## 整体思路

```
[BIOS RTC Wake]          每天定时从关机状态上电
        │
        ▼
[Windows 自动登录]        开机直接进桌面（不用输密码）
        │
        ▼
[Docker Desktop 自启]     跟随登录自动启动 Docker 引擎
        │
        ▼
[容器 restart 策略]       Docker 起来后，之前带 --restart unless-stopped
                          的容器自动恢复运行（pgvector + ExoCore 前后端）
        │
        ▼
[任务计划 autostart.ps1]  兜底：即使 restart 策略漏了，也会再 compose up -d
```

每一步都是独立的保障，层层叠加。

---

## 步骤 1 — BIOS 设置 RTC Wake（定时开机）

这一步**必须重启进 BIOS / UEFI** 设置，Windows 里改不了。

1. 重启电脑，开机时狂按 `Del` 或 `F2`（不同主板不一样）进 BIOS。
2. 找类似下面名字的选项（不同厂商叫法不同）：

   | 厂商 | 选项名可能叫 |
   |------|------------|
   | ASUS | `APM Configuration → Power On By RTC` |
   | MSI | `Settings → Advanced → Wake Up Event Setup → Resume By RTC Alarm` |
   | Gigabyte | `BIOS → Wake On Alarm` |
   | ASRock | `Advanced → ACPI Configuration → RTC Alarm Power On` |

3. 打开开关，设定 `Hour / Minute / Second`（比如每天 09:00:00）。`Day` 通常设 `Every Day`。
4. 保存退出（`F10`）。

**验证方法：** 当天晚上手动关机（不是睡眠），定好时间，第二天到点看电脑会不会自己亮。

> ⚠️ 笔记本电脑：大部分笔记本 BIOS 不支持 RTC Wake。如果是笔记本，改用"睡眠 + 任务计划唤醒"方案（见附录 A）。

---

## 步骤 2 — Windows 自动登录

你已经选了"Windows 设自动登录"，最稳当的办法：

**方法 A：用 netplwiz（推荐）**

1. `Win + R` 打开运行，输入 `netplwiz` 回车。
2. 勾选你的用户，取消上面的 ☑ "要使用本计算机，用户必须输入用户名和密码"。
3. 点"应用"，系统会弹框要你输入两次密码，填完确定。

**如果那个勾选框不见了**（新版 Windows 默认隐藏）：

先在 PowerShell（管理员）里跑：

```powershell
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" -Name "DevicePasswordLessBuildVersion" -Value 0
```

然后重开 `netplwiz`，那个勾就回来了。

**方法 B：注册表手动写入**（不推荐，密码明文存在注册表里）

> 🔒 安全提醒：开了自动登录之后，物理上能摸到你电脑的人就能直接进桌面。如果电脑放在家里别人一般摸不到就问题不大；**一定要开 BitLocker 磁盘加密**（即使被人把硬盘拆走插别机也读不出来）。

---

## 步骤 3 — Docker Desktop 跟随登录自启

1. 打开 Docker Desktop。
2. 右上角齿轮 → `Settings` → `General`。
3. 勾选 **"Start Docker Desktop when you sign in to your computer"**。
4. 顺手看一眼 `Resources` 里内存 / CPU 限额，如果 pgvector 吃得紧可以放宽。

---

## 步骤 4 — 让容器们带上自动重启策略

### 4.1 ExoCore 前后端（已配好）

你项目根目录 `docker-compose.yml` 里 backend 和 frontend 两个 service 都已经有：

```yaml
restart: unless-stopped
```

所以**不用改**。只要第一次 `docker compose up -d` 过，以后 Docker 重启时它们会自动恢复运行。

### 4.2 pgvector（你需要检查一下）

因为 pgvector 是你**单独 `docker run` 出来的**，重启策略取决于你当初那条命令里有没有 `--restart`。在 PowerShell 跑一下查：

```powershell
docker inspect --format '{{.Name}} -> {{.HostConfig.RestartPolicy.Name}}' $(docker ps -a --format '{{.Names}}')
```

找到你 pgvector 容器对应的那行，如果显示 `no` 或 `""`，说明没配，按下面改：

```powershell
# 把 pgvector 改成 "自动重启"（不用重建容器，热改）
docker update --restart unless-stopped pgvector
# 把 pgvector 换成你实际的容器名
```

如果你当初是这样起的（典型写法）：

```powershell
docker run -d --name pgvector --restart unless-stopped `
  -e POSTGRES_PASSWORD=exocore_dev `
  -e POSTGRES_DB=exocore `
  -p 5432:5432 `
  -v pgdata:/var/lib/postgresql/data `
  pgvector/pgvector:pg16
```

那就已经 OK 了。

> 💡 **可选优化**：你可以把 pgvector 也合并进 `ExoCore_Project/docker-compose.yml`，变成一条 `docker compose up -d` 起全家桶。如果你想这么做我可以帮你改。

---

## 步骤 5 — 注册兜底任务（autostart.ps1）

前面 4 步做完理论上就够了。但为了保险（避免 Docker 没起完、网络未就绪等边角 bug），再加一个任务计划作为兜底。

脚本文件：`D:\Alicia\ExoCore_Project\autostart.ps1`（我已经放在项目根目录）

### 5.1 手动试跑一次

先在 PowerShell 里直接跑一遍，看有没有报错：

```powershell
cd D:\Alicia\ExoCore_Project
.\autostart.ps1
```

结果会同时打印在终端和 `autostart.log` 里。

### 5.2 注册到"任务计划程序"

1. 按 `Win`，搜 `任务计划程序`（Task Scheduler），打开。
2. 右侧 "创建任务…"（不要点"创建基本任务"，功能少）。
3. **常规** 选项卡：
   - 名称：`ExoCore Autostart`
   - 选择 "不管用户是否登录都要运行" 或 "只在用户登录时运行" 均可；推荐后者（配合自动登录）。
   - 勾 "使用最高权限运行"。
4. **触发器** 选项卡 → 新建：
   - 开始任务：`登录时`
   - 用户：你自己那个账号
   - （可选）延迟 1 分钟，等 Docker Desktop 起来
5. **操作** 选项卡 → 新建：
   - 操作：`启动程序`
   - 程序或脚本：`powershell.exe`
   - 添加参数（A）：`-ExecutionPolicy Bypass -File "D:\Alicia\ExoCore_Project\autostart.ps1"`
   - 起始于（O）：`D:\Alicia\ExoCore_Project`
6. **条件** 选项卡：
   - 取消 "只有在计算机使用交流电源时才启动"（否则笔记本拔掉电源会不跑）。
7. 保存。

### 5.3 验证

重启一次电脑，登录后等 2-3 分钟，到项目目录看 `autostart.log` 里有没有新的 `ExoCore autostart end` 那一行；再 `docker ps` 看容器都在跑。

---

## 故障排查

**Q：开了 RTC Wake，电脑还是不自己开。**
- 确认 BIOS 里真的 Enable 了，有些主板要同时关 Deep S5 / ErP。
- 确认电脑是真关机（Shutdown）不是"快速启动"留的假关机。可以去 `控制面板 → 电源选项 → 选择电源按钮的功能 → 更改当前不可用的设置` 里把"启用快速启动"取消。

**Q：开机进桌面了，但 Docker 没起。**
- 看 Docker Desktop → Settings → General 里那个勾在不在。
- 系统托盘 Docker 图标右键看状态。

**Q：Docker 起了，但容器没起。**
- 跑 `docker ps -a` 看容器状态和 exit code。
- 跑 `.\autostart.ps1` 手动触发，看 log 里报什么错。
- `docker logs backend` / `docker logs pgvector` 看具体服务报错。

**Q：在 Tailscale 里访问后端还是"未连接"。**
- 参考上次那次诊断：`docker-compose.yml` 的 `ALLOWED_HOSTS` 和 `CSRF_TRUSTED_ORIGINS` 要包含 Tailscale 地址。

---

## 附录 A — 笔记本方案（睡眠代替关机）

如果主板不支持 RTC Wake（笔记本常见），改成：

1. PC 进睡眠而不是关机（`shutdown /h` 是休眠，`rundll32.exe powrprof.dll,SetSuspendState 0,1,0` 是睡眠）。
2. 在任务计划里新建一个触发器 "按计划 / 每天 09:00"，并在 **条件** 里勾 "唤醒计算机运行此任务"。
3. 操作留空 / 或者就跑 `autostart.ps1`。

这种情况下 Windows 不用重开、Docker 也不用重启，容器继续跑；醒过来只是把显示和网络恢复。

---

## 附录 B — 日志位置汇总

- autostart 脚本日志：`D:\Alicia\ExoCore_Project\autostart.log`
- 任务计划自带记录：任务计划程序 → ExoCore Autostart → 历史
- Docker 容器日志：`docker logs <container>`
- 后端 Django 日志：容器里 gunicorn stdout，用 `docker logs backend -f` 看
