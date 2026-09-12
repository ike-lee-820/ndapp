#!/data/data/com.termux/files/usr/bin/bash
# Termux 专用：修复 Gradle 9 兼容性并编译

set +e

PROJECT_DIR="${1:-$HOME/NetdiskUpload}"
cd "$PROJECT_DIR" || { echo "❌ 目录不存在: $PROJECT_DIR"; exit 1; }

echo "=========================================="
echo "  NetdiskUpload Termux 修复脚本"
echo "=========================================="
echo "  项目目录: $PROJECT_DIR"
echo ""

# ============ 检测 Java ============
if ! command -v java >/dev/null 2>&1; then
    echo "❌ 未找到 Java，请先: pkg install openjdk-17"
    exit 1
fi
echo "✓ Java: $(java -version 2>&1 | head -1)"

# ============ 检测 Gradle ============
if ! command -v gradle >/dev/null 2>&1; then
    echo "❌ 未找到 gradle"
    exit 1
fi
GRADLE_VER=$(gradle -v 2>/dev/null | grep -E '^Gradle' | awk '{print $2}')
echo "✓ Gradle: $GRADLE_VER"
echo ""

# ============ 备份 ============
echo "==> 备份原配置..."
[ -f build.gradle ] && cp build.gradle "build.gradle.bak.$(date +%s)"
[ -f app/build.gradle ] && cp app/build.gradle "app/build.gradle.bak.$(date +%s)"
[ -f settings.gradle ] && cp settings.gradle "settings.gradle.bak.$(date +%s)"
echo "✓ 备份完成"
echo ""

# ============ 禁用 init.gradle ============
if [ -f "$HOME/.gradle/init.gradle" ]; then
    echo "==> 禁用全局 init.gradle（避免仓库冲突）..."
    mv "$HOME/.gradle/init.gradle" "$HOME/.gradle/init.gradle.bak"
    echo "✓ 已禁用"
fi

# ============ 写入新 settings.gradle ============
echo "==> 写入 settings.gradle..."
cat > settings.gradle << 'EOF'
pluginManagement {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/public' }
        google()
        mavenCentral()
    }
}
rootProject.name = "NetdiskUpload"
include ':app'
EOF
echo "✓ settings.gradle 写入完成"

# ============ 写入根 build.gradle ============
echo "==> 写入 build.gradle（AGP 8.7.3 + Kotlin 2.0.21）..."
cat > build.gradle << 'EOF'
plugins {
    id 'com.android.application' version '8.7.3' apply false
    id 'org.jetbrains.kotlin.android' version '2.0.21' apply false
}
EOF
echo "✓ build.gradle 写入完成"

# ============ 写入 app/build.gradle ============
echo "==> 写入 app/build.gradle..."
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
    implementation 'androidx.core:core-ktx:1.13.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.12.0'
    implementation 'androidx.documentfile:documentfile:1.0.1'
    implementation 'androidx.lifecycle:lifecycle-runtime-ktx:2.8.7'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1'
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
}
EOF
echo "✓ app/build.gradle 写入完成"

# ============ 更新 gradle.properties ============
echo "==> 更新 gradle.properties..."
cat > gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.caching=true
android.aapt2FromMavenOverride=/data/data/com.termux/files/usr/bin/aapt2
EOF
echo "✓ gradle.properties 写入完成"
echo ""

# ============ 检测 Android SDK ============
SDK_DIR=""
if [ -n "$ANDROID_HOME" ]; then SDK_DIR="$ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ]; then SDK_DIR="$ANDROID_SDK_ROOT"
elif [ -d "$HOME/android-sdk" ]; then SDK_DIR="$HOME/android-sdk"
fi

if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    echo "⚠️  未找到 Android SDK"
    echo "   请先执行:"
    echo "   export ANDROID_HOME=\$HOME/android-sdk"
    echo "   \$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \"platforms;android-34\" \"build-tools;34.0.0\""
    exit 1
fi

echo "✓ Android SDK: $SDK_DIR"
echo "sdk.dir=$SDK_DIR" > local.properties
echo ""

# ============ 清理缓存 ============
echo "==> 清理旧缓存..."
rm -rf .gradle build app/build
echo "✓ 清理完成"
echo ""

# ============ 判断 Gradle 版本 ============
GRADLE_MAJOR=$(echo "$GRADLE_VER" | cut -d. -f1)
GRADLE_MINOR=$(echo "$GRADLE_VER" | cut -d. -f2)

USE_GRADLE="$GRADLE_VER"

if [ "$GRADLE_MAJOR" -ge 10 ] || { [ "$GRADLE_MAJOR" -eq 9 ] && [ "$GRADLE_MINOR" -ge 6 ]; }; then
    echo "⚠️  检测到 Gradle $GRADLE_VER（≥9.6）与 AGP 8.x 不兼容"
    echo "==> 自动下载 Gradle 9.5..."
    
    if [ ! -d "$HOME/gradle95" ]; then
        cd "$HOME"
        if [ ! -f gradle-9.5-bin.zip ]; then
            echo "   下载 Gradle 9.5..."
            wget -q --show-progress https://services.gradle.org/distributions/gradle-9.5-bin.zip \
                || wget -q --show-progress https://mirrors.cloud.tencent.com/gradle/gradle-9.5-bin.zip
        fi
        unzip -q gradle-9.5-bin.zip
        mv gradle-9.5 gradle95
        cd "$PROJECT_DIR"
    fi
    
    USE_GRADLE="$HOME/gradle95/bin/gradle"
    echo "✓ 使用 $USE_GRADLE"
    echo ""
fi

# ============ 编译 ============
echo "=========================================="
echo "  开始编译"
echo "=========================================="
echo ""
echo "首次编译可能需要 10-20 分钟，请耐心等待..."
echo ""

$USE_GRADLE assembleDebug 2>&1 | tee /tmp/build.log | tail -50

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "  ✓ 编译成功"
    echo "=========================================="
    APK_PATH="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
    if [ -f "$APK_PATH" ]; then
        echo "APK: $APK_PATH"
        ls -lh "$APK_PATH"
        echo ""
        echo "安装:"
        echo "  adb install -r \"$APK_PATH\""
        echo "  或把 APK 传到手机手动安装"
    fi
else
    echo "  ❌ 编译失败"
    echo "=========================================="
    echo ""
    echo "最后 30 行日志:"
    tail -30 /tmp/build.log
    echo ""
    echo "完整日志: /tmp/build.log"
    echo ""
    echo "常见问题:"
    echo "  1. SDK 缺失 → sdkmanager \"platforms;android-34\" \"build-tools;34.0.0\""
    echo "  2. 内存不足 → 减少其他 App，给 Termux 无限制后台"
    echo "  3. 网络慢 → 挂代理，或换阿里云镜像"
    echo "  4. 仍报 AGP 版本错 → 手动降级 Gradle 8.5"
    echo ""
fi

echo "=========================================="
