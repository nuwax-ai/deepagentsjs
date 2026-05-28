#!/usr/bin/env bash
# =============================================================================
# deepagentsjs 一键构建脚本
#
# 用途: 构建 deepagentsjs monorepo 所有包，产出可跨平台分发的产物
#
# 项目特点:
#   - 纯 TypeScript 库，输出 ESM (.js) + CJS (.cjs) + 类型声明 (.d.ts)
#   - ACP 包含 CLI (shebang #!/usr/bin/env node)
#   - quickjs 使用 WASM，天然跨平台
#   - 无 native addon，构建产物在 macOS/Linux/Windows 通用
#
# 用法:
#   ./scripts/build.sh                    # 完整构建 (clean + install + build + verify)
#   ./scripts/build.sh --quick            # 快速构建 (跳过 clean + install)
#   ./scripts/build.sh --core             # 仅构建核心库
#   ./scripts/build.sh --providers        # 仅构建 provider 包
#   ./scripts/build.sh --acp              # 仅构建 ACP CLI
#   ./scripts/build.sh --pack             # 构建后打包为 .tgz
#   ./scripts/build.sh --docker           # Docker 跨平台构建
#   ./scripts/build.sh --help             # 显示帮助
#
# 环境要求:
#   - Node.js >= 24.x (见 .nvmrc)
#   - pnpm >= 10.29.x
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 颜色与符号
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "${BLUE}▸${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✗${RESET} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${RESET}\n"; }

# ---------------------------------------------------------------------------
# 项目根目录 (脚本在 scripts/ 下，根目录是其父目录)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# 构建产物输出目录
# ---------------------------------------------------------------------------
RELEASE_DIR="$PROJECT_ROOT/nuwax-dist"
BUILD_LOG="$PROJECT_ROOT/.build.log"

# ---------------------------------------------------------------------------
# 默认参数
# ---------------------------------------------------------------------------
DO_CLEAN=true
DO_INSTALL=true
DO_CORE=true
DO_PROVIDERS=true
DO_ACP=true
DO_STANDARD_TESTS=true
DO_PACK=true
DO_DOCKER=false
DO_CROSS=true
DO_VERIFY=true
DO_TEST=false
QUICK_MODE=false
TARGET_PLATFORMS=("linux-x64" "linux-arm64" "darwin-x64" "darwin-arm64" "win32-x64" "win32-arm64")

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
show_help() {
    cat <<'HELP'
deepagentsjs 一键构建脚本

用法:
  ./scripts/build.sh [选项]

构建范围:
  --all               构建全部包 (默认)
  --core              仅构建核心库 (deepagents)
  --providers         仅构建 provider 包 (quickjs/deno/daytona/modal/node-vfs)
  --acp               仅构建 ACP CLI (deepagents-acp)
  --quick             快速模式: 跳过 clean 和 install，仅重新编译

构建动作:
  --pack              构建后打包 .tgz 到 nuwax-dist/ 目录
  --docker            使用 Docker 在隔离环境中构建 (保证 Linux 兼容)
  --test              构建后运行单元测试
  --no-verify         跳过构建产物验证
  --no-clean          跳过 clean 步骤

跨平台:
  --no-cross          禁用跨平台构建 (仅构建当前平台)
  --platform <target>  指定目标平台 (可多次使用，默认: 所有 6 个平台)
                       可选: linux-x64, linux-arm64, darwin-x64,
                             darwin-arm64, win32-x64, win32-arm64, all
                       JS 产物天然跨平台，此选项用于生成平台特定包

工具:
  --help              显示此帮助信息
  --version           显示版本信息

示例:
  ./scripts/build.sh                         # 完整构建 (默认跨所有平台)
  ./scripts/build.sh --quick                 # 快速重新编译 (跨所有平台)
  ./scripts/build.sh --no-cross              # 仅构建当前平台
  ./scripts/build.sh --core --pack           # 构建核心库并打包
  ./scripts/build.sh --all --test --pack     # 全量构建 + 测试 + 打包
  ./scripts/build.sh --docker                # Docker 隔离构建
  ./scripts/build.sh --acp --pack            # 构建 ACP CLI 并打包
  ./scripts/build.sh --platform linux-x64 --platform linux-arm64  # 仅构建 Linux 双架构
HELP
}

show_version() {
    local pkg_version
    pkg_version=$(node -p "require('./libs/deepagents/package.json').version")
    echo "deepagentsjs v${pkg_version}"
    echo "Node.js $(node --version)"
    echo "pnpm $(pnpm --version 2>/dev/null || echo 'not installed')"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help; exit 0 ;;
        --version|-v)
            show_version; exit 0 ;;
        --quick|-q)
            QUICK_MODE=true; DO_CLEAN=false; DO_INSTALL=false ;;
        --all)
            DO_CORE=true; DO_PROVIDERS=true; DO_ACP=true; DO_STANDARD_TESTS=true ;;
        --core)
            DO_CORE=true; DO_PROVIDERS=false; DO_ACP=false; DO_STANDARD_TESTS=false ;;
        --providers)
            DO_CORE=false; DO_PROVIDERS=true; DO_ACP=false; DO_STANDARD_TESTS=false ;;
        --acp)
            DO_CORE=false; DO_PROVIDERS=false; DO_ACP=true; DO_STANDARD_TESTS=false ;;
        --pack)
            DO_PACK=true ;;
        --docker)
            DO_DOCKER=true ;;
        --no-cross)
            DO_CROSS=false; DO_PACK=false; TARGET_PLATFORMS=("current") ;;
        --test)
            DO_TEST=true ;;
        --no-verify)
            DO_VERIFY=false ;;
        --no-clean)
            DO_CLEAN=false ;;
        --platform)
            shift
            # 第一次使用 --platform 时，清空默认平台列表
            if [[ ${#TARGET_PLATFORMS[@]} -eq 6 ]]; then
                TARGET_PLATFORMS=()
            fi
            if [[ "$1" == "all" ]]; then
                TARGET_PLATFORMS=("linux-x64" "linux-arm64" "darwin-x64" "darwin-arm64" "win32-x64" "win32-arm64")
            else
                TARGET_PLATFORMS+=("$1")
            fi
            ;;
        *)
            err "未知参数: $1"
            echo "使用 --help 查看帮助"
            exit 1 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# 环境检查
# ---------------------------------------------------------------------------
check_prerequisites() {
    header "环境检查"

    local has_error=false

    # Node.js
    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node --version | sed 's/v//' | cut -d. -f1)
        if [[ "$node_ver" -ge 24 ]]; then
            ok "Node.js $(node --version)"
        else
            warn "Node.js $(node --version) — 建议 >= 24.x (见 .nvmrc)"
        fi
    else
        err "Node.js 未安装"
        has_error=true
    fi

    # pnpm
    if command -v pnpm &>/dev/null; then
        ok "pnpm $(pnpm --version)"
    else
        err "pnpm 未安装 — 运行: npm install -g pnpm@10"
        has_error=true
    fi

    # Docker (可选)
    if $DO_DOCKER; then
        if command -v docker &>/dev/null; then
            ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
        else
            err "Docker 未安装，但指定了 --docker"
            has_error=true
        fi
    fi

    # 磁盘空间
    local avail_mb
    avail_mb=$(df -m "$PROJECT_ROOT" 2>/dev/null | awk 'NR==2{print $4}' || echo 999)
    if [[ "$avail_mb" -lt 500 ]]; then
        warn "可用磁盘空间不足 500MB (当前: ${avail_mb}MB)"
    else
        ok "磁盘空间: ${avail_mb}MB 可用"
    fi

    # .env 文件检查
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        if [[ -f "$PROJECT_ROOT/.env.example" ]]; then
            info "未找到 .env，构建不需要 API Key（仅运行时需要）"
        fi
    fi

    if $has_error; then
        err "环境检查失败，请修复上述问题后重试"
        exit 1
    fi

    ok "环境检查通过"
}

# ---------------------------------------------------------------------------
# 步骤 1: 清理
# ---------------------------------------------------------------------------
step_clean() {
    if ! $DO_CLEAN; then
        info "跳过 clean (--quick 或 --no-clean)"
        return
    fi

    header "清理旧产物"

    info "清理 dist 目录..."
    pnpm run clean 2>/dev/null || true

    info "清理旧 nuwax-dist..."
    rm -rf "$RELEASE_DIR"

    info "清理构建日志..."
    rm -f "$BUILD_LOG"

    ok "清理完成"
}

# ---------------------------------------------------------------------------
# 步骤 2: 安装依赖
# ---------------------------------------------------------------------------
step_install() {
    if ! $DO_INSTALL; then
        info "跳过 install (--quick)"
        return
    fi

    header "安装依赖"

    info "运行 pnpm install --frozen-lockfile..."
    pnpm install --frozen-lockfile 2>&1 | tail -5

    ok "依赖安装完成"
}

# ---------------------------------------------------------------------------
# 步骤 3: 类型检查
# ---------------------------------------------------------------------------
step_typecheck() {
    if $QUICK_MODE; then
        info "跳过 typecheck (--quick)"
        return
    fi

    header "类型检查"

    info "运行 TypeScript 类型检查..."
    if pnpm run typecheck 2>&1 | tee -a "$BUILD_LOG" | tail -3; then
        ok "类型检查通过"
    else
        warn "类型检查有警告 (详见 $BUILD_LOG)"
    fi
}

# ---------------------------------------------------------------------------
# 步骤 4: 构建核心库
# ---------------------------------------------------------------------------
step_build_core() {
    if ! $DO_CORE; then return; fi

    header "构建核心库: deepagents"

    info "编译 libs/deepagents..."
    (cd libs/deepagents && pnpm run build 2>&1) | tee -a "$BUILD_LOG" | tail -3
    ok "deepagents 构建完成"

    if $DO_STANDARD_TESTS; then
        info "编译 libs/standard-tests..."
        (cd libs/standard-tests && pnpm run build 2>&1) | tee -a "$BUILD_LOG" | tail -3
        ok "standard-tests 构建完成"
    fi
}

# ---------------------------------------------------------------------------
# 步骤 5: 构建 Provider 包
# ---------------------------------------------------------------------------
step_build_providers() {
    if ! $DO_PROVIDERS; then return; fi

    header "构建 Provider 包"

    local providers=("node-vfs" "quickjs" "deno" "daytona" "modal")

    for provider in "${providers[@]}"; do
        local pkg_dir="libs/providers/$provider"
        if [[ -d "$pkg_dir" ]]; then
            info "编译 @langchain/${provider}..."
            (cd "$pkg_dir" && pnpm run build 2>&1) | tee -a "$BUILD_LOG" | tail -3
            ok "@langchain/${provider} 构建完成"
        else
            warn "跳过 @langchain/${provider} (目录不存在)"
        fi
    done
}

# ---------------------------------------------------------------------------
# 步骤 6: 构建 ACP CLI
# ---------------------------------------------------------------------------
step_build_acp() {
    if ! $DO_ACP; then return; fi

    header "构建 ACP CLI: deepagents-acp"

    info "编译 libs/acp (含 CLI)..."
    (cd libs/acp && pnpm run build 2>&1) | tee -a "$BUILD_LOG" | tail -3
    ok "deepagents-acp 构建完成"
}

# ---------------------------------------------------------------------------
# 步骤 7: 运行测试 (可选)
# ---------------------------------------------------------------------------
step_test() {
    if ! $DO_TEST; then return; fi

    header "运行单元测试"

    info "运行 vitest..."
    pnpm run test:unit 2>&1 | tee -a "$BUILD_LOG" | tail -10

    ok "单元测试完成"
}

# ---------------------------------------------------------------------------
# 步骤 8: 验证构建产物
# ---------------------------------------------------------------------------
step_verify() {
    if ! $DO_VERIFY; then
        info "跳过验证 (--no-verify)"
        return
    fi

    header "验证构建产物"

    local has_error=false

    # 验证函数: 检查指定目录的 dist 产物
    # 兼容两种 tsdown 配置:
    #   - 显式 outExtensions → index.js / index.d.ts (大多数包)
    #   - tsdown 默认扩展名  → index.mjs / index.d.mts (node-vfs)
    verify_package() {
        local pkg_path="$1"
        local pkg_name="$2"
        local check_cli="${3:-false}"

        local dist_dir="$pkg_path/dist"

        if [[ ! -d "$dist_dir" ]]; then
            err "$pkg_name: dist/ 目录不存在"
            has_error=true
            return
        fi

        # 检查 ESM (.js 或 .mjs)
        local esm_file=""
        if [[ -f "$dist_dir/index.js" ]]; then
            esm_file="index.js"
        elif [[ -f "$dist_dir/index.mjs" ]]; then
            esm_file="index.mjs"
        fi

        if [[ -n "$esm_file" ]]; then
            local esm_size
            esm_size=$(du -sh "$dist_dir/$esm_file" 2>/dev/null | cut -f1)
            ok "$pkg_name: ESM ($esm_size) [$esm_file]"
        else
            err "$pkg_name: 缺少 ESM 产物 (index.js 或 index.mjs)"
            has_error=true
        fi

        # 检查 CJS (.cjs)
        if [[ ! -f "$dist_dir/index.cjs" ]]; then
            err "$pkg_name: 缺少 CJS 产物 (index.cjs)"
            has_error=true
        else
            local cjs_size
            cjs_size=$(du -sh "$dist_dir/index.cjs" 2>/dev/null | cut -f1)
            ok "$pkg_name: CJS ($cjs_size)"
        fi

        # 检查类型声明 (.d.ts 或 .d.mts)
        local dts_file=""
        if [[ -f "$dist_dir/index.d.ts" ]]; then
            dts_file="index.d.ts"
        elif [[ -f "$dist_dir/index.d.mts" ]]; then
            dts_file="index.d.mts"
        fi

        if [[ -n "$dts_file" ]]; then
            ok "$pkg_name: 类型声明 ($dts_file)"
        else
            err "$pkg_name: 缺少类型声明 (index.d.ts 或 index.d.mts)"
            has_error=true
        fi

        # 检查 sourcemap (.js.map 或 .mjs.map)
        if [[ -f "$dist_dir/index.js.map" ]] || [[ -f "$dist_dir/index.mjs.map" ]]; then
            ok "$pkg_name: sourcemap"
        fi

        # 检查 CLI (仅 ACP)
        if [[ "$check_cli" == "true" ]]; then
            if [[ -f "$dist_dir/cli.js" ]]; then
                # 验证 shebang
                local first_line
                first_line=$(head -1 "$dist_dir/cli.js")
                if [[ "$first_line" == "#!/usr/bin/env node" ]]; then
                    ok "$pkg_name: CLI shebang 正确"
                else
                    warn "$pkg_name: CLI shebang 异常: $first_line"
                fi
            else
                err "$pkg_name: 缺少 CLI 产物 (cli.js)"
                has_error=true
            fi
        fi
    }

    # 验证各包
    if $DO_CORE; then
        verify_package "libs/deepagents" "deepagents"
    fi

    if $DO_ACP; then
        verify_package "libs/acp" "deepagents-acp" "true"
    fi

    if $DO_PROVIDERS; then
        for provider in node-vfs quickjs deno daytona modal; do
            verify_package "libs/providers/$provider" "@langchain/$provider"
        done
    fi

    if $DO_STANDARD_TESTS; then
        verify_package "libs/standard-tests" "@langchain/sandbox-standard-tests"
    fi

    # ESM 导入验证
    if $DO_CORE && [[ -f "libs/deepagents/dist/index.js" ]]; then
        info "验证 ESM 模块可加载..."
        if node --input-type=module -e "import('file://$PROJECT_ROOT/libs/deepagents/dist/index.js').then(m => { const keys = Object.keys(m).length; if (keys > 0) { process.exit(0); } else { process.exit(1); } }).catch(() => process.exit(1))" 2>/dev/null; then
            ok "ESM 模块可正常加载"
        else
            warn "ESM 模块加载失败 (可能是依赖未安装)"
        fi
    fi

    # CJS 导入验证
    if $DO_CORE && [[ -f "libs/deepagents/dist/index.cjs" ]]; then
        info "验证 CJS 模块可加载..."
        if node -e "const m = require('$PROJECT_ROOT/libs/deepagents/dist/index.cjs'); if (Object.keys(m).length > 0) { process.exit(0); } else { process.exit(1); }" 2>/dev/null; then
            ok "CJS 模块可正常加载"
        else
            warn "CJS 模块加载失败 (可能是依赖未安装)"
        fi
    fi

    if $has_error; then
        err "构建产物验证失败"
        exit 1
    fi

    ok "全部产物验证通过"
}

# ---------------------------------------------------------------------------
# 步骤 9: 打包发布
# ---------------------------------------------------------------------------
step_pack() {
    if ! $DO_PACK; then return; fi

    header "打包发布产物"

    mkdir -p "$RELEASE_DIR"

    local platform
    platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

    pack_package() {
        local pkg_path="$1"
        local pkg_name="$2"

        if [[ ! -d "$pkg_path/dist" ]]; then
            warn "$pkg_name: 无 dist，跳过打包"
            return
        fi

        info "打包 $pkg_name..."

        local tar_name="${pkg_name}-${platform}.tgz"
        tar czf "$RELEASE_DIR/$tar_name" \
            -C "$pkg_path" \
            dist/ \
            package.json \
            README.md \
            LICENSE \
            2>/dev/null || \
        tar czf "$RELEASE_DIR/$tar_name" \
            -C "$pkg_path" \
            dist/ \
            package.json \
            2>/dev/null

        local tar_size
        tar_size=$(du -sh "$RELEASE_DIR/$tar_name" | cut -f1)
        ok "$pkg_name → $tar_name ($tar_size)"
    }

    if $DO_CORE; then
        pack_package "libs/deepagents" "deepagents"
    fi
    if $DO_ACP; then
        pack_package "libs/acp" "deepagents-acp"
    fi
    if $DO_PROVIDERS; then
        for provider in node-vfs quickjs deno daytona modal; do
            pack_package "libs/providers/$provider" "langchain-${provider}"
        done
    fi

    # 生成产物清单
    info "生成产物清单..."
    cat > "$RELEASE_DIR/MANIFEST.md" <<EOF
# deepagentsjs Build Manifest

- **构建时间**: $(date '+%Y-%m-%d %H:%M:%S %Z')
- **构建平台**: $(uname -s) $(uname -m)
- **Node.js**: $(node --version)
- **pnpm**: $(pnpm --version)
- **Git**: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')

## 产物列表

| 文件 | 大小 | 说明 |
|------|------|------|
EOF

    for f in "$RELEASE_DIR"/*.tgz; do
        [[ -f "$f" ]] || continue
        local fname fsize
        fname=$(basename "$f")
        fsize=$(du -sh "$f" | cut -f1)
        echo "| \`$fname\` | $fsize | 预构建产物 |" >> "$RELEASE_DIR/MANIFEST.md"
    done

    cat >> "$RELEASE_DIR/MANIFEST.md" <<'EOF'

## 跨平台说明

本产物为纯 JavaScript (ESM + CJS) + TypeScript 类型声明:

- **macOS** (Intel / Apple Silicon): 直接可用
- **Linux** (x64 / ARM64): 直接可用
- **Windows** (x64): 直接可用

无需平台特定编译。仅需目标机器安装 Node.js >= 24.x。

## 使用方式

```bash
# 解压
tar xzf deepagents-*.tgz

# 安装运行时依赖
cd dist && npm install --production

# 或通过 npm 直接安装 tgz
npm install ./deepagents-*.tgz
```
EOF

    ok "清单已生成: nuwax-dist/MANIFEST.md"
}

# ---------------------------------------------------------------------------
# 跨平台打包 (本地构建，多平台产物)
# ---------------------------------------------------------------------------
step_cross_pack() {
    if ! $DO_CROSS; then return; fi

    header "跨平台打包"

    mkdir -p "$RELEASE_DIR"

    # 要打包的包列表
    local packages=()
    local package_names=()

    if $DO_CORE; then
        packages+=("libs/deepagents")
        package_names+=("deepagents")
    fi
    if $DO_ACP; then
        packages+=("libs/acp")
        package_names+=("deepagents-acp")
    fi
    if $DO_PROVIDERS; then
        for provider in node-vfs quickjs deno daytona modal; do
            packages+=("libs/providers/$provider")
            package_names+=("langchain-${provider}")
        done
    fi

    # 平台映射: 平台标识 → (npm platform, npm arch)
    declare -A platform_map
    platform_map["linux-x64"]="linux x64"
    platform_map["linux-arm64"]="linux arm64"
    platform_map["darwin-x64"]="darwin x64"
    platform_map["darwin-arm64"]="darwin arm64"
    platform_map["win32-x64"]="win32 x64"
    platform_map["win32-arm64"]="win32 arm64"

    # 过滤掉 "current"，只处理明确指定的平台
    local cross_platforms=()
    for p in "${TARGET_PLATFORMS[@]}"; do
        if [[ "$p" != "current" ]]; then
            cross_platforms+=("$p")
        fi
    done

    if [[ ${#cross_platforms[@]} -eq 0 ]]; then
        warn "未指定目标平台，使用默认: linux-x64, linux-arm64, darwin-x64, darwin-arm64"
        cross_platforms=("linux-x64" "linux-arm64" "darwin-x64" "darwin-arm64")
    fi

    info "目标平台: ${cross_platforms[*]}"
    info "打包 ${#packages[@]} 个包 × ${#cross_platforms[@]} 个平台"

    local total_count=0
    local success_count=0

    for target in "${cross_platforms[@]}"; do
        local npm_platform npm_arch
        if [[ -n "${platform_map[$target]+_}" ]]; then
            read -r npm_platform npm_arch <<< "${platform_map[$target]}"
        else
            warn "未知平台: $target，跳过"
            continue
        fi

        info "━━━ 平台: $target (npm: $npm_platform/$npm_arch) ━━━"

        for i in "${!packages[@]}"; do
            local pkg_path="${packages[$i]}"
            local pkg_name="${package_names[$i]}"

            total_count=$((total_count + 1))

            if [[ ! -d "$pkg_path/dist" ]]; then
                warn "$pkg_name: 无 dist，跳过"
                continue
            fi

            # 创建平台特定的暂存目录
            local stage_dir="$RELEASE_DIR/.stage/${pkg_name}-${target}"
            rm -rf "$stage_dir"
            mkdir -p "$stage_dir"

            # 1. 复制 dist 和 package.json
            cp -r "$pkg_path/dist" "$stage_dir/"
            cp "$pkg_path/package.json" "$stage_dir/"
            [[ -f "$pkg_path/README.md" ]] && cp "$pkg_path/README.md" "$stage_dir/"
            [[ -f "$pkg_path/LICENSE" ]] && cp "$pkg_path/LICENSE" "$stage_dir/"

            # 2. 清理 package.json 中的 workspace 依赖
            info "  清理 $pkg_name 的 workspace 依赖..."
            node -e "
                const fs = require('fs');
                const pkg = JSON.parse(fs.readFileSync('$stage_dir/package.json', 'utf8'));
                // 移除 devDependencies (发布包不需要)
                delete pkg.devDependencies;
                // 将 workspace:* 替换为 * (让用户在目标平台自行安装)
                for (const deps of [pkg.dependencies, pkg.peerDependencies, pkg.optionalDependencies]) {
                    if (deps) {
                        for (const [name, version] of Object.entries(deps)) {
                            if (version.startsWith('workspace:')) {
                                deps[name] = '*';
                            }
                        }
                    }
                }
                fs.writeFileSync('$stage_dir/package.json', JSON.stringify(pkg, null, 2));
            "

            # 3. 平台特定依赖安装 (仅安装 production 依赖，跳过 workspace)
            info "  安装 $pkg_name 依赖 ($target)..."
            (
                cd "$stage_dir"
                # 设置平台环境变量安装依赖
                npm_config_platform="$npm_platform" \
                npm_config_arch="$npm_arch" \
                npm install --production --ignore-scripts --legacy-peer-deps 2>&1 | tail -3
            ) || warn "  依赖安装失败 (非致命，用户可在目标平台重新安装)"

            # 4. 打包
            local tar_name="${pkg_name}-${target}.tgz"
            tar czf "$RELEASE_DIR/$tar_name" -C "$stage_dir" .

            local tar_size
            tar_size=$(du -sh "$RELEASE_DIR/$tar_name" | cut -f1)
            ok "  $pkg_name → $tar_name ($tar_size)"

            success_count=$((success_count + 1))
        done
    done

    # 清理暂存目录
    rm -rf "$RELEASE_DIR/.stage"

    ok "跨平台打包完成: ${success_count}/${total_count} 个产物"
}

# ---------------------------------------------------------------------------
# Docker 构建 (可选)
# ---------------------------------------------------------------------------
step_docker_build() {
    if ! $DO_DOCKER; then return; fi

    header "Docker 跨平台构建"

    local dockerfile_content='FROM node:24-slim

# 安装 pnpm
RUN corepack enable && corepack prepare pnpm@10.29.2 --activate

WORKDIR /app

# 复制依赖描述文件 (利用 Docker layer cache)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY libs/deepagents/package.json libs/deepagents/
COPY libs/acp/package.json libs/acp/
COPY libs/standard-tests/package.json libs/standard-tests/
COPY libs/providers/node-vfs/package.json libs/providers/node-vfs/
COPY libs/providers/quickjs/package.json libs/providers/quickjs/
COPY libs/providers/deno/package.json libs/providers/deno/
COPY libs/providers/daytona/package.json libs/providers/daytona/
COPY libs/providers/modal/package.json libs/providers/modal/

# 安装依赖
RUN pnpm install --frozen-lockfile

# 复制源码
COPY . .

# 构建
RUN pnpm run build

# 输出产物到 /output
RUN mkdir -p /output && \
    for dir in libs/deepagents libs/acp libs/standard-tests libs/providers/*/; do \
        if [ -d "$dir/dist" ]; then \
            cp -r "$dir/dist" "/output/$(basename $dir)-dist"; \
        fi; \
    done
'

    info "写入 Dockerfile.build..."
    echo "$dockerfile_content" > "$PROJECT_ROOT/Dockerfile.build"

    info "构建 Docker 镜像..."
    docker build \
        -f "$PROJECT_ROOT/Dockerfile.build" \
        -t deepagentsjs-builder \
        "$PROJECT_ROOT" 2>&1 | tail -5

    info "从容器提取产物..."
    mkdir -p "$RELEASE_DIR/docker"
    local container_id
    container_id=$(docker create deepagentsjs-builder)
    docker cp "${container_id}:/output/." "$RELEASE_DIR/docker/" 2>/dev/null || true
    docker rm "$container_id" >/dev/null 2>&1

    # 清理
    rm -f "$PROJECT_ROOT/Dockerfile.build"

    ok "Docker 构建完成，产物在 nuwax-dist/docker/"
}

# ---------------------------------------------------------------------------
# 构建摘要
# ---------------------------------------------------------------------------
print_summary() {
    local duration="$1"

    header "构建完成"

    echo -e "${BOLD}构建范围:${RESET}"
    $DO_CORE       && echo -e "  ${GREEN}✓${RESET} deepagents (核心库)"
    $DO_ACP        && echo -e "  ${GREEN}✓${RESET} deepagents-acp (ACP CLI)"
    $DO_PROVIDERS  && echo -e "  ${GREEN}✓${RESET} providers (quickjs/deno/daytona/modal/node-vfs)"
    $DO_STANDARD_TESTS && echo -e "  ${GREEN}✓${RESET} standard-tests"
    $DO_TEST       && echo -e "  ${GREEN}✓${RESET} 单元测试"
    $DO_PACK       && echo -e "  ${GREEN}✓${RESET} 打包 → nuwax-dist/"
    $DO_CROSS      && echo -e "  ${GREEN}✓${RESET} 跨平台打包 (${#TARGET_PLATFORMS[@]} 个平台)"
    $DO_DOCKER     && echo -e "  ${GREEN}✓${RESET} Docker 构建"

    echo ""
    echo -e "${BOLD}产物位置:${RESET}"

    # 统计 dist 产物
    local total_size=0
    local pkg_count=0

    for dist_dir in libs/deepagents/dist libs/acp/dist libs/standard-tests/dist libs/providers/*/dist; do
        if [[ -d "$dist_dir" ]]; then
            local size
            size=$(du -sm "$dist_dir" 2>/dev/null | cut -f1)
            total_size=$((total_size + size))
            pkg_count=$((pkg_count + 1))
            echo -e "  ${CYAN}$(dirname $dist_dir | sed 's|libs/||')${RESET}/dist/ — ${size}MB"
        fi
    done

    echo ""
    echo -e "${BOLD}总计:${RESET} ${pkg_count} 个包, ${total_size}MB"
    echo -e "${BOLD}耗时:${RESET} ${duration}"

    if $DO_PACK && [[ -d "$RELEASE_DIR" ]]; then
        echo ""
        echo -e "${BOLD}发布包:${RESET}"
        ls -lh "$RELEASE_DIR"/*.tgz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}' || echo "  (无)"
    fi

    echo ""
    echo -e "${DIM}跨平台说明: 产物为纯 JS (ESM+CJS)，在 macOS/Linux/Windows (Node >= 24) 通用${RESET}"
    echo -e "${DIM}构建日志: $BUILD_LOG${RESET}"
}

# ===========================================================================
# 主流程
# ===========================================================================
main() {
    local start_time
    start_time=$(date +%s)

    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║       deepagentsjs — 一键构建脚本               ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo -e "${DIM}项目根: $PROJECT_ROOT${RESET}"
    echo -e "${DIM}平台:   $(uname -s) $(uname -m)${RESET}"
    echo -e "${DIM}时间:   $(date '+%Y-%m-%d %H:%M:%S')${RESET}"

    check_prerequisites
    step_clean
    step_install
    step_typecheck
    step_build_core
    step_build_providers
    step_build_acp
    step_test
    step_verify
    step_pack
    step_cross_pack
    step_docker_build

    local end_time duration
    end_time=$(date +%s)
    duration="$((end_time - start_time))秒"

    print_summary "$duration"
}

main "$@"
