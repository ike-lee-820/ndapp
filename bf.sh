#!/data/data/com.termux/files/usr/bin/bash
# Termux 专用：Gradle 8.5 + AGP 8.2.0 稳定方案

set +e

PROJECT_DIR="${1:-$HOME/NetdiskUpload}"
cd "$PROJECT_DIR" || { echo "❌ 目录不存在: $PROJECT_DIR"; exit 1; }

echo "=========================================="
echo "  NetdiskUpload 编译脚本 (Gradle 8.5)"
echo "=========================================="
echo "  项目目录: $PROJECT_DIR"
echo ""

# ============ 1. 检测 Java ============
if ! command -v java >/dev/null 2>&1; then
    echo "❌ 未找到 Java，请先: pkg install openjdk-17"
    exit 1
fi
echo "✓ Java: $(java -version 2>&1 | head -1 | cut -d'"' -f2)"

# ============ 2. 下载 Gradle 8.5（如果不存在） ============
if [ ! -x "$HOME/gradle85/bin/gradle" ]; then
    echo "==> 下载 Gradle 8.5..."
    cd "$HOME"
    if [ ! -f gradle-8.5-bin.zip ]; then
        wget -q --show-progress https://services.gradle.org/distributions/gradle-8.5-bin.zip \
            || wget -q --show-progress https://mirrors.cloud.tencent.com/gradle/gradle-8.5-bin.zip \
            || { echo "❌ 下载失败，请检查网络"; exit 1; }
    fi
    unzip -q gradle-8.5-bin.zip
    mv gradle-8.5 gradle85
    cd "$PROJECT_DIR"
    echo "✓ Gradle 8.5 安装完成"
else
    echo "✓ Gradle 8.5 已存在"
fi

GRADLE_BIN="$HOME/gradle85/bin/gradle"
$GRADLE_BIN -v | head -5
echo ""

# ============ 3. 禁用全局 init.gradle ============
if [ -f "$HOME/.gradle/init.gradle" ]; then
    echo "==> 禁用全局 init.gradle..."
    mv "$HOME/.gradle/init.gradle" "$HOME/.gradle/init.gradle.bak.$(date +%s)"
    echo "✓ 已禁用"
fi

# ============ 4. 写入配置文件 ============
echo "==> 写入配置文件..."

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

cat > build.gradle << 'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.20' apply false
}
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
org.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
org.gradle.daemon=true
org.gradle.parallel=false
org.gradle.caching=true
EOF

echo "✓ 配置文件写入完成"
echo ""

# ============ 5. 检测 Android SDK ============
SDK_DIR=""
if [ -n "$ANDROID_HOME" ]; then SDK_DIR="$ANDROID_HOME"
elif [ -n "$ANDROID_SDK_ROOT" ]; then SDK_DIR="$ANDROID_SDK_ROOT"
elif [ -d "$HOME/android-sdk" ]; then SDK_DIR="$HOME/android-sdk"
fi

if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
    echo "❌ 未找到 Android SDK"
    echo "   请先安装:"
    echo "   export ANDROID_HOME=\$HOME/android-sdk"
    echo "   \$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \"platforms;android-34\" \"build-tools;34.0.0\""
    exit 1
fi

echo "✓ Android SDK: $SDK_DIR"
echo "sdk.dir=$SDK_DIR" > local.properties

# 检查必备组件
if [ ! -d "$SDK_DIR/platforms/android-34" ]; then
    echo "⚠️  缺少 platforms;android-34，正在安装..."
    yes | "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" "platforms;android-34" 2>/dev/null
fi
if [ ! -d "$SDK_DIR/build-tools/34.0.0" ]; then
    echo "⚠️  缺少 build-tools;34.0.0，正在安装..."
    yes | "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" "build-tools;34.0.0" 2>/dev/null
fi
echo ""

# ============ 6. 清理缓存 ============
echo "==> 清理旧缓存..."
rm -rf .gradle build app/build
echo "✓ 清理完成"
echo ""

# ============ 7. 编译 ============
echo "=========================================="
echo "  开始编译 (Gradle 8.5 + AGP 8.2.0)"
echo "=========================================="
echo ""
echo "首次编译 10-20 分钟，请保持 Termux 前台运行"
echo ""

$GRADLE_BIN assembleDebug 2>&1 | tee /tmp/build85.log | tail -60
EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "=========================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "  ✓ 编译成功"
    echo "=========================================="
    APK_PATH="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
    if [ -f "$APK_PATH" ]; then
        echo ""
        echo "APK: $APK_PATH"
        ls -lh "$APK_PATH"
        echo ""
        echo "安装:"
        echo "  adb install -r \"$APK_PATH\""
        echo "  或传到手机手动安装"
        echo ""
    fi
else
    echo "  ❌ 编译失败"
    echo "=========================================="
    echo ""
    echo "最后 30 行日志:"
    tail -30 /tmp/build85.log
    echo ""
    echo "完整日志: /tmp/build85.log"
fi

echo ""
echo "日常使用: 以后编译只需执行"
echo "  cd $PROJECT_DIR && ~/gradle85/bin/gradle assembleDebug"
