# xingchen-llama-pc-deploy

Uploading xingchen-use.mp4…


两种方案，从零到对话只需 10 分钟

## 一、模型简介
XingChen4-29B 是 DeepSeek-V4 风格的 MoE 架构大模型（MLA + MoE + HC 定制），总参数 29B，int4权重采用 IQ4_NL 混合精度量化，量化后约 18GB（两个 GGUF 分片），可在单张消费级 GPU 上运行。
本文提供两种部署方案，按需选择：
| | 方案一：一键编译 | 方案二：免编译分发 |
|---|---|---|
| **适合人群** | 开发者、需要灵活定制 | 普通用户、快速上手 |
| **前提条件** | 安装 Git、CMake、VS2022、CUDA Toolkit | 仅需 NVIDIA 显卡驱动 |
| **操作步骤** | 运行 PowerShell 脚本，自动编译启动 | 解压、放模型、双击 bat |
| **耗时** | 首次约 15-30 分钟（编译） | 3 分钟（解压 + 启动） |
| **文件大小** | 脚本约 16KB | 预编译包约 390MB |

## 二、方案一：一键编译部署
### 2.1 环境准备
以下软件需提前安装，安装后重启终端使环境变量生效：
1. **Git**  下载：https://git-scm.com
2. **CMake**  下载：https://cmake.org/download
3. **Visual Studio 2022**（勾选"使用 C++ 的桌面开发"）  下载：https://visualstudio.microsoft.com/downloads
4. **CUDA Toolkit**（需与 GPU 驱动版本匹配）  下载：https://developer.nvidia.com/cuda-toolkit-archive
验证环境：
```
git --version
cmake --version
nvcc --version
```
三条命令都有输出，说明环境就绪。
### 2.2 获取脚本
将部署脚本 deploy-xingchen4.ps1 放到当前工作目录，脚本会在此目录下自动克隆 llama.cpp 仓库。
### 2.3 运行脚本
在 PowerShell 中执行：
```
.\deploy-xingchen4.ps1
```
脚本会自动完成以下 7 个步骤：
```
步骤	说明
Step 1	检查依赖（Git、CMake、VS2022、nvcc）
Step 2	自动检测 CUDA Toolkit 路径
Step 3	克隆 / 更新 llama.cpp 仓库
Step 4	切换到 xingchen4-port 分支
Step 5	下载 Web UI 静态资源（从 HF 镜像）
Step 6	编译 llama.cpp（GPU 或 CPU 后端）
Step 7	启动 llama-server 并自动打开浏览器
```
### 2.4 可选参数
脚本支持以下参数，按需指定：
```
# CPU 模式（不使用 GPU）
.\deploy-xingchen4.ps1 -Backend cpu
# 自定义端口
.\deploy-xingchen4.ps1 -Port 8086
# 自定义模型路径
.\deploy-xingchen4.ps1 -ModelPath "D:\models\xingchen4-iq4-00001-of-00002.gguf"
# 自定义上下文长度
.\deploy-xingchen4.ps1 -ContextSize 65536
```
完整参数列表：
| 参数 | 默认值 | 说明 |
|---|---|---|
| `-ModelPath` | 无 | 模型文件路径 |
| `-ContextSize` | 262144 | 上下文窗口大小 |
| `-Backend` | gpu | 后端选择：gpu 或 cpu |
| `-GpuLayers` | 999 | GPU 层数（0 = 纯 CPU） |
| `-Port` | 8086 | 服务端口 |
| `-HostAddr` | 0.0.0.0 | 监听地址 |
| `-StaticPath` | 自动检测 | Web UI 静态文件目录 |

### 2.5 编译完成后
编译成功后，脚本会自动启动服务并打开浏览器。看到类似输出说明成功：
```
[OK] Build complete
[OK] Starting API server: http://0.0.0.0:8086
```
浏览器会自动弹出对话页面，即可开始使用。

## 三、方案二：免编译分发
### 3.1 适用场景
●目标机器与编译机器同型号 GPU
●已安装 NVIDIA 显卡驱动
●不想安装开发工具链（Git / CMake / VS2022 / CUDA Toolkit）
### 3.2 部署包内容
部署包是一个文件夹，包含以下文件：
| 文件 | 说明 | 大小 |
|---|---|---|
| `llama-server.exe` | 静态编译的推理引擎（含嵌入式 Web UI） | ~43 MB |
| `cudart64_13.dll` | CUDA 运行时库 | ~0.5 MB |
| `cublas64_13.dll` | CUDA 矩阵运算库 | ~51 MB |
| `cublasLt64_13.dll` | CUDA 矩阵运算库（轻量版） | ~453 MB |
| `run-server.bat` | 一键启动脚本 | ~2 KB |
| `xingchen4-iq4-00001-of-00002.gguf` | 模型分片 1 | ~9.7 GB |
| `xingchen4-iq4-00002-of-00002.gguf` | 模型分片 2 | ~9.0 GB |

模型即将开源，欢迎关注TeleAI的huggingface仓库：https://huggingface.co/Tele-AI。
### 3.3 部署步骤
Step 1：解压部署包
将整个文件夹拷贝到目标机器任意目录（如 D:\xingchen4-deploy\）。
Step 2：放入模型文件
如果模型文件不在部署包中，将两个 GGUF 分片放入部署目录，与 run-server.bat 同级：
```
D:\xingchen4-deploy\
  ├── llama-server.exe
  ├── cudart64_13.dll
  ├── cublas64_13.dll
  ├── cublasLt64_13.dll
  ├── run-server.bat
  ├── xingchen4-iq4-00001-of-00002.gguf    ← 放这里
  └── xingchen4-iq4-00002-of-00002.gguf    ← 放这里
```
Step 3：双击启动
双击 run-server.bat，会弹出命令行窗口显示启动日志，随后浏览器自动打开对话页面。
看到以下输出说明启动成功：
```
model loaded
listening on http://0.0.0.0:8086
```
浏览器地址栏会自动跳转到对应服务端，即可开始对话。
### 3.4 自定义参数
用记事本打开 run-server.bat，修改文件顶部的参数值即可，无需碰下方的启动逻辑：
```
set MODEL=xingchen4-iq4-00001-of-00002.gguf   rem 模型文件名
set NGL=999                                    rem GPU层数（0=纯CPU）
set CTX=65536                                  rem 上下文长度
set NTOKENS=8192                               rem 最大生成token数
set FA=on                                      rem Flash Attention
set CACHEK=q8_0                                rem KV缓存量化
set CACHEV=q8_0
set PORT=8086                                  rem 端口
set HOST=0.0.0.0                               rem 监听地址
set STATICPATH=                                rem Web UI目录（空=用内置）
```
常见参数：
| 需求 | 修改 |
|---|---|
| 减少显存占用 | `set CTX=32768`（减小上下文） |
| 纯 CPU 运行 | `set NGL=0` |
| 更换端口 | `set PORT=8086` |
| 仅本机访问 | `set HOST=127.0.0.1` |

## 四、两种方案对比
| 维度 | 方案一：一键编译 | 方案二：免编译分发 |
|---|---|---|
| 首次耗时 | 15-30 分钟 | 3 分钟 |
| 环境要求 | Git + CMake + VS2022 + CUDA Toolkit | 仅显卡驱动 |
| 灵活性 | 可修改源码、切换分支、调整编译选项 | 仅可调启动参数 |
| 可移植性 | 任意 Windows + CUDA 机器 | 需同型号 GPU |
| 更新方式 | git pull + 重新编译 | 重新分发部署包 |
| 适用场景 | 开发调试、提交 PR、适配新模型 | 快速部署 |
建议：如果你是开发者，用方案一；如果你只是想跑起来用，用方案二。

## 五、常见问题
Q: 启动后浏览器显示 “Server unavailable”
检查命令行窗口是否有报错。常见原因：模型文件路径不对、端口被占用、GPU 显存不足。

Q: 浏览器打开的是 0.0.0.0:8086，页面无法访问
0.0.0.0 是服务端监听地址，客户端需用 http://127.0.0.1:8086 访问。run-server.bat 已自动用 127.0.0.1 打开浏览器。

Q: CUDA DLL 缺失报错
方案二中，三个 CUDA DLL 必须和 llama-server.exe 在同一目录。如果目标机器 GPU 型号不同，需替换为对应版本的 CUDA DLL。

Q: 显存不够
减小上下文大小（-c 65536 或更小）、使用 KV 缓存量化（--cache-type-k q8_0 --cache-type-v q8_0）、减少 GPU 层数（-ngl 值）。

Q: CPU 模式怎么用
方案一：.\deploy-xingchen4.ps1 -Backend cpu
方案二：编辑 run-server.bat，将 set NGL=0。

## 六、技术架构
```
用户浏览器 (127.0.0.1:8086)
        |
        v
  llama-server.exe  ← 静态编译，内含 ggml + llama + Web UI
        |
        +-- GPU 后端 (CUDA)  ← cudart64 / cublas64 / cublasLt64
        |
        +-- CPU 后端 (AVX2)  ← 自动回退
        |
        v
  XingChen4-29B GGUF 模型文件 (IQ4_NL 量化)
```
llama-server 是基于 llama.cpp 的 HTTP 推理服务，提供 OpenAI 兼容的 API 接口和内置 Web UI 对话页面。静态编译将 ggml 计算库、llama 模型库、Web UI 资源全部嵌入单个 exe，运行时仅需 CUDA 运行时 DLL。
![星辰模型部署示例](https://raw.githubusercontent.com/shuxiaoqiong/xingchen-llama-pc-deploy/main/%E6%98%9F%E8%BE%B0%E6%A8%A1%E5%9E%8B%E9%83%A8%E7%BD%B2%E7%A4%BA%E4%BE%8B.png)

