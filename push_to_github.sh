#!/data/data/com.termux/files/usr/bin/bash
# 推送到 GitHub 并配置 Actions 编译

set -e

PROJECT_DIR="${1:-$HOME/NetdiskUpload}"
GITHUB_USER="ike-lee-820"
GITHUB_REPO="ndapp"
REPO_URL="git@github.com:$GITHUB_USER/$GITHUB_REPO.git"

cd "$PROJECT_DIR"

echo "=========================================="
echo "  推送到 $GITHUB_USER/$GITHUB_REPO"
echo "=========================================="
echo ""

# ============ 1. 检查 SSH ============
if ! ssh -T git@github.com 2>&1 | grep -q "Hi $GITHUB_USER"; then
    echo "❌ SSH 未配置，请先完成:"
    echo "   1. ssh-keygen -t ed25519 -C 'termux@android' -f ~/.ssh/id_ed25519 -N ''"
    echo "   2. cat ~/.ssh/id_ed25519.pub  → 添加到 github.com/settings/keys"
    echo "   3. ssh -T git@github.com  → 应显示 Hi $GITHUB_USER"
    exit 1
fi
echo "✓ SSH 已配置"
echo ""

# ============ 2. 检查项目 ============
if [ ! -f settings.gradle ]; then
    echo "❌ 当前目录不是 Android 项目: $PROJECT_DIR"
    exit 1
fi
echo "✓ 项目目录: $PROJECT_DIR"

# 检查关键文件
for f in app/build.gradle app/src/main/java/com/example/netdisk/MainActivity.kt \
         app/src/main/java/com/example/netdisk/UploadService.kt; do
    if [ ! -f "$f" ]; then
        echo "❌ 缺少文件: $f"
        exit 1
    fi
done
echo "✓ 关键文件齐全"
echo ""

# ============ 3. 生成 GitHub Actions 配置 ============
echo "==> 生成 .github/workflows/build.yml..."
mkdir -p .github/workflows

cat > .github/workflows/build.yml << 'YAML_EOF'
name: Build APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3
        with:
          packages: 'platforms;android-34 build-tools;34.0.0'

      - name: Cache Gradle
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: gradle-

      - name: Grant execute permission
        run: chmod +x gradlew || true

      - name: Build Debug APK
        run: gradle assembleDebug --no-daemon --stacktrace

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: app/build/outputs/apk/debug/app-debug.apk
          retention-days: 30
YAML_EOF

echo "✓ workflow 已生成"
echo ""

# ============ 4. 生成 .gitignore ============
echo "==> 生成 .gitignore..."
cat > .gitignore << 'EOF'
*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build
/app/build
/captures
.externalNativeBuild
.cxx
local.properties
*.apk
*.aab
*.log
EOF
echo "✓ .gitignore 已生成"
echo ""

# ============ 5. 初始化 Git 仓库 ============
echo "==> 初始化 Git 仓库..."
if [ ! -d .git ]; then
    git init
    git branch -M main
fi

# 配置用户信息（如果没有）
if ! git config user.email >/dev/null 2>&1; then
    git config user.email "$GITHUB_USER@users.noreply.github.com"
fi
if ! git config user.name >/dev/null 2>&1; then
    git config user.name "$GITHUB_USER"
fi

echo "✓ Git 初始化完成"
echo ""

# ============ 6. 添加远程仓库 ============
if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REPO_URL"
else
    git remote add origin "$REPO_URL"
fi
echo "✓ 远程仓库: $REPO_URL"
echo ""

# ============ 7. 提交并推送 ============
echo "==> 添加文件并提交..."
git add -A
git commit -m "Android netdisk upload client" 2>/dev/null || echo "无新变更"

echo "==> 推送到 GitHub..."
echo ""
git push -u origin main 2>&1 || {
    echo ""
    echo "⚠️  推送失败，可能是:"
    echo "   1. 仓库不存在 → 先去 github.com/new 创建 $GITHUB_REPO"
    echo "   2. 首次推送需要接受 host key → 手动运行一次 ssh -T git@github.com"
    echo "   3. 权限问题 → 确认 SSH key 添加到 GitHub"
    exit 1
}

echo ""
echo "=========================================="
echo "  ✓ 推送成功"
echo "=========================================="
echo ""
echo "接下来:"
echo "  1. 浏览器打开 https://github.com/$GITHUB_USER/$GITHUB_REPO/actions"
echo "  2. 等待 1-3 分钟"
echo "  3. 点最新的 Build APK 运行记录"
echo "  4. 页面底部 Artifacts → 下载 app-debug.zip"
echo "  5. 解压得 app-debug.apk，传到手机安装"
echo ""
