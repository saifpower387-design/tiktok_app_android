#!/usr/bin/env python3
"""Android setup for the generated Flutter android/ folder (run from the repo root by codemagic.yaml).

Every step validates its own result and fails loudly with a clear message, so a broken
build points at the real cause instead of a vague Gradle/Flutter error later on.
"""
import json
import os
import re
import shutil
import sys
import xml.dom.minidom
from pathlib import Path

ROOT = Path.cwd()
ANDROID = ROOT / 'android'
APP = ANDROID / 'app'
MANIFEST = APP / 'src/main/AndroidManifest.xml'

ADMOB_APP_ID = 'ca-app-pub-5663628720448893~5879440187'
PACKAGE_NAME = 'com.example.tiktok_app'
CAMERA_KIT_VERSION = '1.26.0'


def fail(msg):
    print(f'ERROR: {msg}')
    sys.exit(1)


def first_existing(*paths):
    for p in paths:
        p = Path(p)
        if p.exists():
            return p
    fail('Missing file: ' + ' or '.join(str(p) for p in paths))


def version_tuple(v):
    return tuple(int(x) for x in re.findall(r'\d+', v)[:3])


# --------------------------------------------------------------------------- manifest
def setup_manifest():
    text = MANIFEST.read_text()

    if 'xmlns:tools' not in text:
        text = text.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

    wanted = ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS',
              'ACCESS_NETWORK_STATE', 'ACCESS_WIFI_STATE']
    perms = ''.join(
        f'    <uses-permission android:name="android.permission.{p}"/>\n'
        for p in wanted if f'android.permission.{p}"' not in text
    )
    if perms:
        if '<application' not in text:
            fail('<application> tag not found in AndroidManifest.xml')
        text = text.replace('<application', perms + '    <application', 1)

    # NOTE: the meta-data / activity elements must go AFTER the opening <application ...> tag,
    # never inside it (that was the cause of "android manifest is not a valid XML document").
    extra = ''
    if 'com.google.android.gms.ads.APPLICATION_ID' not in text:
        extra += (
            '\n        <meta-data\n'
            '            android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
            f'            android:value="{ADMOB_APP_ID}" />\n'
        )
    # Camera Kit's CameraActivity extends AppCompatActivity but its own manifest declares NO theme.
    # Flutter's default application theme is not AppCompat, so the app crashed the moment the
    # Snap camera opened. Give the activity an AppCompat theme explicitly.
    if 'com.snap.camerakit.support.app.CameraActivity' not in text:
        extra += (
            '\n        <activity\n'
            '            android:name="com.snap.camerakit.support.app.CameraActivity"\n'
            '            android:theme="@style/Theme.AppCompat.NoActionBar"\n'
            '            android:screenOrientation="portrait"\n'
            '            android:exported="false" />\n'
        )
    if extra:
        text, n = re.subn(r'(<application\b[^>]*?>)', lambda m: m.group(1) + extra, text, count=1, flags=re.S)
        if n != 1:
            fail('Could not find the <application ...> opening tag')

    xml.dom.minidom.parseString(text)  # validate before saving
    MANIFEST.write_text(text)
    print('AndroidManifest.xml OK')


# --------------------------------------------------------------------------- MainActivity (Snap Camera Kit)
KOTLIN = '''package __PACKAGE__

import android.net.Uri
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.snap.camerakit.support.app.CameraActivity
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val cameraKitApiToken = __TOKEN__
    private val cameraKitGroupId = __GROUP__
    private val channelName = "st_video/snap_camera"
    private var pendingResult: MethodChannel.Result? = null

    // content:// و file:// الاتنين مدعومين، وأي خطأ بيرجع للتطبيق كرسالة بدل ما يقفله
    private fun resolvePath(uri: Uri, ext: String): String? {
        return try {
            if (uri.scheme == "file") {
                uri.path
            } else {
                val out = File(cacheDir, "snap_" + System.currentTimeMillis() + "." + ext)
                contentResolver.openInputStream(uri)?.use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
                out.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }

    private val captureLauncher =
        registerForActivityResult(CameraActivity.Capture) { captureResult ->
            val result = pendingResult
            pendingResult = null
            try {
                when (captureResult) {
                    is CameraActivity.Capture.Result.Success.Video -> {
                        val path = resolvePath(captureResult.uri, "mp4")
                        if (path != null) result?.success(mapOf("path" to path, "mime_type" to "video"))
                        else result?.error("NO_FILE", "تعذر قراءة الفيديو", null)
                    }
                    is CameraActivity.Capture.Result.Success.Image -> {
                        val path = resolvePath(captureResult.uri, "jpg")
                        if (path != null) result?.success(mapOf("path" to path, "mime_type" to "image"))
                        else result?.error("NO_FILE", "تعذر قراءة الصورة", null)
                    }
                    is CameraActivity.Capture.Result.Cancelled -> {
                        result?.error("CANCELLED", "تم إلغاء التصوير", null)
                    }
                    is CameraActivity.Capture.Result.Failure -> {
                        result?.error("CAMERA_KIT_FAILURE", "فشل تشغيل Camera Kit", null)
                    }
                }
            } catch (e: Exception) {
                result?.error("CAMERA_KIT_FAILURE", e.message ?: "خطأ غير معروف", null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "openCameraKitLenses") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingResult != null) {
                    result.error("BUSY", "كاميرا Snap مفتوحة بالفعل", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                try {
                    captureLauncher.launch(
                        CameraActivity.Configuration.WithLenses(
                            cameraKitApiToken = cameraKitApiToken,
                            lensGroupIds = arrayOf(cameraKitGroupId)
                        )
                    )
                } catch (e: Throwable) {
                    pendingResult = null
                    result.error("LAUNCH_FAILED", e.message ?: "تعذر فتح كاميرا Snap", null)
                }
            }
    }
}
'''


def setup_snap():
    token = os.environ.get('SNAP_CAMERA_KIT_API_TOKEN')
    group = os.environ.get('SNAP_CAMERA_KIT_GROUP_ID')
    if not token or not group:
        fail('Missing SNAP_CAMERA_KIT_API_TOKEN / SNAP_CAMERA_KIT_GROUP_ID in Codemagic environment variables')

    kotlin_root = APP / 'src/main/kotlin'
    main_activity = next(kotlin_root.rglob('MainActivity.kt'), None)
    if main_activity is None:
        fail('Flutter did not generate MainActivity.kt')
    package = '.'.join(main_activity.relative_to(kotlin_root).parts[:-1])
    src = (KOTLIN.replace('__PACKAGE__', package)
           .replace('__TOKEN__', json.dumps(token))
           .replace('__GROUP__', json.dumps(group)))
    main_activity.write_text(src)
    print('Wrote MainActivity.kt for package', package)


# --------------------------------------------------------------------------- gradle
def setup_app_gradle():
    gradle = first_existing(APP / 'build.gradle.kts', APP / 'build.gradle')
    kts = gradle.suffix == '.kts'
    text = gradle.read_text()

    # SDK levels (only lines that start with the property name -> no accidental matches)
    text = re.sub(r'(?m)^(\s*)compileSdk(?:Version)?\b.*$', r'\1compileSdk = 36', text)
    text = re.sub(r'(?m)^(\s*)targetSdk(?:Version)?\b.*$', r'\1targetSdk = 36', text)
    text = re.sub(r'(?m)^(\s*)minSdk(?:Version)?\b.*$', r'\1minSdk = 24', text)

    # Fixed debug signing key (android/app/debug.keystore is copied by the workflow).
    # The debug build type uses signingConfigs.debug automatically, no buildTypes edit needed.
    if 'debug.keystore' not in text:
        if kts:
            signing = ('\n    signingConfigs {\n        getByName("debug") {\n'
                       '            storeFile = file("debug.keystore")\n'
                       '            storePassword = "android"\n            keyAlias = "androiddebugkey"\n'
                       '            keyPassword = "android"\n        }\n    }\n')
        else:
            signing = ('\n    signingConfigs {\n        debug {\n'
                       '            storeFile file("debug.keystore")\n'
                       '            storePassword "android"\n            keyAlias "androiddebugkey"\n'
                       '            keyPassword "android"\n        }\n    }\n')
        if 'android {' not in text:
            fail('android { block not found in app Gradle file')
        text = text.replace('android {', 'android {' + signing, 1)

    # Camera Kit dependency
    if 'com.snap.camerakit:support-camera-activity' not in text:
        dep = (f'    implementation("com.snap.camerakit:support-camera-activity:{CAMERA_KIT_VERSION}")\n' if kts
               else f'    implementation "com.snap.camerakit:support-camera-activity:{CAMERA_KIT_VERSION}"\n')
        if re.search(r'(?m)^dependencies\s*\{', text):
            text = re.sub(r'(?m)^dependencies\s*\{', lambda m: m.group(0) + '\n' + dep, text, count=1)
        else:
            text += '\n\ndependencies {\n' + dep + '}\n'

    # Java 8+ for Camera Kit
    if 'sourceCompatibility' not in text:
        opts = ('\n    compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_17\n'
                '        targetCompatibility = JavaVersion.VERSION_17\n    }\n')
        text = text.replace('android {', 'android {' + opts, 1)

    # google-services plugin (applied right after the flutter plugin line)
    if 'com.google.gms.google-services' not in text:
        line = 'id("com.google.gms.google-services")' if kts else 'id "com.google.gms.google-services"'
        text, n = re.subn(r'(?m)^(\s*)(id\(?\s*"dev\.flutter\.flutter-gradle-plugin"\)?)\s*$',
                          lambda m: m.group(0) + '\n' + m.group(1) + line, text, count=1)
        if n != 1:
            fail('Could not find flutter-gradle-plugin line in app Gradle file')
    gradle.write_text(text)
    print('app Gradle file updated:', gradle)


def setup_settings_gradle():
    settings = first_existing(ANDROID / 'settings.gradle.kts', ANDROID / 'settings.gradle')
    kts = settings.suffix == '.kts'
    text = settings.read_text()

    if 'com.google.gms.google-services' not in text:
        line = ('    id("com.google.gms.google-services") version "4.4.2" apply false' if kts
                else '    id "com.google.gms.google-services" version "4.4.2" apply false')
        # insert inside the *top-level* plugins { } block (the one that declares AGP / loader)
        m = re.search(r'(?m)^plugins\s*\{', text)
        if not m:
            fail('plugins { block not found in settings.gradle')
        text = text[:m.end()] + '\n' + line + text[m.end():]

    # Adaptive toolchain: only upgrade when the template is too old for compileSdk 36 / current plugins.
    agp = re.search(r'com\.android\.application"\)?\s*version\s*"([\d.]+)"', text)
    if agp and version_tuple(agp.group(1)) < (8, 9, 1):
        print(f'AGP {agp.group(1)} is too old, upgrading to 8.9.1')
        text = text.replace(agp.group(0), agp.group(0).replace(agp.group(1), '8.9.1'))
        bump_wrapper('8.11.1')
    kotlin = re.search(r'org\.jetbrains\.kotlin\.android"\)?\s*version\s*"([\d.]+)"', text)
    if kotlin and version_tuple(kotlin.group(1)) < (2, 0, 0):
        print(f'Kotlin {kotlin.group(1)} is too old, upgrading to 2.1.0')
        text = text.replace(kotlin.group(0), kotlin.group(0).replace(kotlin.group(1), '2.1.0'))
    settings.write_text(text)
    print('settings.gradle updated:', settings)


def bump_wrapper(minimum):
    wrapper = ANDROID / 'gradle/wrapper/gradle-wrapper.properties'
    if not wrapper.exists():
        fail(f'Missing Gradle wrapper: {wrapper}')
    text = wrapper.read_text()
    m = re.search(r'gradle-([\d.]+)-(?:bin|all)\.zip', text)
    if m and version_tuple(m.group(1)) >= version_tuple(minimum):
        print('Gradle wrapper', m.group(1), 'is new enough')
        return
    text, n = re.subn(r'distributionUrl=.*',
                      f'distributionUrl=https\\\\://services.gradle.org/distributions/gradle-{minimum}-bin.zip', text)
    if n != 1:
        fail('Could not update Gradle distributionUrl')
    wrapper.write_text(text)
    print('Gradle wrapper set to', minimum)


# --------------------------------------------------------------------------- misc
def setup_keystore():
    ks = ROOT / 'signing/debug.keystore'
    if not ks.exists():
        fail('signing/debug.keystore is missing from the repository')
    home_android = Path.home() / '.android'
    home_android.mkdir(parents=True, exist_ok=True)
    shutil.copy(ks, home_android / 'debug.keystore')
    shutil.copy(ks, APP / 'debug.keystore')
    print('Fixed debug keystore installed')


def setup_icons():
    root = ROOT / 'assets/app_icon'
    if not (root / 'app_icon.png').exists():
        fail('App icon assets are missing')
    for d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']:
        target = APP / f'src/main/res/mipmap-{d}'
        target.mkdir(parents=True, exist_ok=True)
        for name in ['ic_launcher.png', 'ic_launcher_round.png']:
            shutil.copy(root / f'mipmap-{d}' / name, target / name)
    for name in ['ic_launcher.xml', 'ic_launcher_round.xml']:
        (APP / 'src/main/res/mipmap-anydpi-v26' / name).unlink(missing_ok=True)
    print('Launcher icon applied')


def setup_firebase():
    gs = ROOT / 'google-services.json'
    if not gs.exists():
        fail('google-services.json is missing')
    data = json.loads(gs.read_text())
    android = [c for c in data.get('client', [])
               if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == PACKAGE_NAME]
    if not android:
        fail('google-services.json package mismatch')
    oauth = android[0].get('oauth_client', [])
    if not any(c.get('client_type') == 1 for c in oauth):
        fail('google-services.json has no Android OAuth client (add the SHA-1 in Firebase console)')
    if not any(c.get('client_type') == 3 for c in oauth):
        fail('google-services.json has no Web OAuth client')
    shutil.copy(gs, APP / 'google-services.json')
    print('Firebase config OK')


if __name__ == '__main__':
    setup_keystore()
    setup_icons()
    setup_firebase()
    setup_snap()
    setup_manifest()
    setup_settings_gradle()
    setup_app_gradle()
    print('Android setup finished')
