#!/data/data/com.termux/files/usr/bin/bash
# GitHub Actions 一键修复：AGP 8.2.0 + Gradle 8.5

set -e

PROJECT_DIR="${1:-$HOME/NetdiskUpload}"
cd "$PROJECT_DIR"

GITHUB_USER="ike-lee-820"
GITHUB_REPO="ndapp"

echo "=========================================="
echo "  GitHub Actions 一键修复"
echo "=========================================="
echo ""

# ============ 1. 检查 SSH ============
if ! ssh -T git@github.com 2>&1 | grep -q "Hi $GITHUB_USER"; then
    echo "❌ SSH 未配置，请先:"
    echo "   ssh-keygen -t ed25519 -C 'termux@android' -f ~/.ssh/id_ed25519 -N ''"
    echo "   cat ~/.ssh/id_ed25519.pub → 加到 github.com/settings/keys"
    exit 1
fi
echo "✓ SSH 已配置"
echo ""

# ============ 2. 降级 AGP 到 8.2.0 ============
echo "==> 配置 AGP 8.2.0 + Kotlin 1.9.20..."

cat > build.gradle << 'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.20' apply false
}
EOF

cat > settings.gradle << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "NetdiskUpload"
include ':app'
EOF

cat > app/build.gradle << 'EOF'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.example.netdisk'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.netdisk"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }

    buildFeatures { viewBinding true }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }

    buildTypes {
        release { minifyEnabled false }
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.documentfile:documentfile:1.0.1'
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.7.0'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
EOF

cat > gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=true
EOF

echo "✓ build.gradle / settings.gradle / app/build.gradle 已更新"
echo ""

# ============ 3. 生成 gradle wrapper ============
echo "==> 生成 gradle wrapper (8.5)..."

mkdir -p gradle/wrapper

cat > gradle/wrapper/gradle-wrapper.properties << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# 下载 gradle-wrapper.jar 和 gradlew
if [ ! -f gradle/wrapper/gradle-wrapper.jar ] || [ ! -f gradlew ]; then
    echo "==> 下载 gradle-wrapper.jar..."
    
    # 检查是否有本地 gradle 8.x
    if [ -x "$HOME/gradle85/bin/gradle" ]; then
        cd "$PROJECT_DIR"
        "$HOME/gradle85/bin/gradle" wrapper --gradle-version 8.5 2>&1 | tail -5
        echo "✓ 用本地 gradle 生成 wrapper"
    else
        # 从 GitHub 直接拉取
        mkdir -p $HOME$HOME/tmp/gw
        cd $HOME$HOME/tmp/gw
        wget -q https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradle/wrapper/gradle-wrapper.jar -O gradle-wrapper.jar || {
            echo "❌ 下载 gradle-wrapper.jar 失败，请手动运行:"
            echo "   cd $PROJECT_DIR && ~/gradle85/bin/gradle wrapper"
            exit 1
        }
        cp gradle-wrapper.jar "$PROJECT_DIR/gradle/wrapper/"
        
        # 下载 gradlew 脚本
        wget -q https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradlew -O "$PROJECT_DIR/gradlew"
        wget -q https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradlew.bat -O "$PROJECT_DIR/gradlew.bat"
        
        cd "$PROJECT_DIR"
        chmod +x gradlew
        echo "✓ 从 GitHub 下载 wrapper 完成"
    fi
fi

chmod +x gradlew 2>/dev/null || true
echo "✓ gradlew 权限设置完成"
echo ""

# ============ 4. 重写 workflow ============
echo "==> 重写 GitHub Actions workflow..."
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
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Grant execute permission for gradlew
        run: chmod +x gradlew

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3
        with:
          packages: 'platforms;android-34 build-tools;34.0.0'

      - name: Build Debug APK
        run: ./gradlew assembleDebug --no-daemon --stacktrace

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: app/build/outputs/apk/debug/app-debug.apk
          retention-days: 30
YAML_EOF

echo "✓ workflow 已重写（使用 gradlew + Gradle 8.5）"
echo ""

# ============ 5. 更新 .gitignore ============
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
*.apk
*.aab
*.log
EOF
echo "✓ .gitignore 已更新"
echo ""

# ============ 6. 清理本地缓存 ============
echo "==> 清理本地缓存..."
rm -rf .gradle build app/build
echo "✓ 清理完成"
echo ""

# ============ 7. 提交并推送 ============
echo "==> 提交并推送..."
git add -A
git commit -m "Fix: AGP 8.2.0 + Gradle 8.5 wrapper for CI stability" 2>&1 | tail -3 || echo "无变更"

# 确保 main 分支
git branch -M main 2>/dev/null || true

git push origin main 2>&1 || {
    echo ""
    echo "⚠️  推送失败，可能原因："
    echo "   1. 远程有更新，先 git pull --rebase"
    echo "   2. 权限问题，检查 SSH: ssh -T git@github.com"
    exit 1
}

echo ""
echo "=========================================="
echo "  ✓ 全部修复完成并推送"
echo "=========================================="
echo ""
echo "下一步："
echo "  1. 打开 https://github.com/$GITHUB_USER/$GITHUB_REPO/actions"
echo "  2. 等待 2-4 分钟"
echo "  3. 编译成功后，点击最新运行记录"
echo "  4. 页面底部 Artifacts → 下载 app-debug.zip"
echo "  5. 解压得到 app-debug.apk"
echo ""
echo "查看编译进度（Termux）:"
echo "  watch -n 10 'curl -s https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/actions/runs | grep -E \"status|conclusion\" | head -4'"
echo ""
