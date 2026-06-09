# ExoCore 启动备忘

## 一条命令（推荐）

```powershell
.\hybrid_start.ps1
```

做的事：pgvector 容器 → Django :8000 → nginx 容器 :8080

启动后打开 **http://localhost:8080**

---

## 日常使用流程

```
# 1. 启动后端 + 前端（一次性）
.\hybrid_start.ps1

# 2. 改了前端代码 → 构建
cd ExoCore-Desktop
pnpm build

# 3. 刷新浏览器即可看到改动
# nginx 通过 volume 挂载 dist/ 目录，无需重启
```

---

## 分别启动

```powershell
# 1. pgvector（首次创建）
docker run -d --name exocore-pg --restart unless-stopped `
  -e POSTGRES_PASSWORD=exocore_dev `
  -e POSTGRES_DB=exocore `
  -p 5432:5432 `
  -v pgdata:/var/lib/postgresql/data `
  pgvector/pgvector:pg16

# 如果已存在
docker start exocore-pg

# 2. Django 后端
cd ExoCore
python.exe manage.py runserver

# 3. 前端 nginx（首次构建镜像）
cd nginx
docker build -t exocore-nginx .
docker run -d --name exocore-nginx --restart unless-stopped `
  -p 8080:80 -p 8443:443 `
  -v D:/Alicia/ExoCore_Project/ExoCore-Desktop/packages/chat-core/dist:/usr/share/nginx/html/chat `
  -v D:/Alicia/ExoCore_Project/ExoCore-Desktop/packages/chronicle/dist:/usr/share/nginx/html/chronicle `
  -v D:/Alicia/ExoCore_Project/ExoCore-Desktop/packages/council/dist:/usr/share/nginx/html/council `
  -v D:/Alicia/ExoCore_Project/mkcertpem:/etc/nginx/certs:ro `
  exocore-nginx
```

---

## 开发模式（不需要 nginx）

```bash
# 纯前端开发，Vite dev server 自带 /api → :8000 proxy
cd ExoCore-Desktop
pnpm dev:chat     # :5173
pnpm dev:chronicle # :5174
pnpm dev:council  # :5175
```

开发模式不需要 nginx，Vite 已配置 proxy。

---

## Docker 只需要两个容器

| 容器 | 镜像 | 端口 |
|------|------|------|
| `exocore-pg` | pgvector/pgvector:pg16 | 5432 |
| `exocore-nginx` | exocore-nginx (本地构建) | 8080→80, 8443→443 |

后端 Django 本地裸跑，不容器化。
