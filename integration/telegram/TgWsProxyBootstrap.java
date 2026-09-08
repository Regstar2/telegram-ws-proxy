package org.telegram.messenger;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import org.json.JSONObject;
import org.telegram.tgnet.ConnectionsManager;
import org.telegram.ui.ActionBar.AlertDialog;
import org.telegram.ui.LaunchActivity;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import io.github.regstar2.tgwsproxy.core.TgWsProxyConfig;
import io.github.regstar2.tgwsproxy.core.TgWsProxyCore;
import io.github.regstar2.tgwsproxy.core.TgWsProxyOperationResult;
import io.github.regstar2.tgwsproxy.core.TgWsProxyStatus;

final class TgWsProxyBootstrap {
    private static final String PREFS = "tgwsproxy";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_SECRET = "secret";
    private static final String KEY_RUNTIME_CONFIG = "runtime_config";
    private static final String KEY_MANAGED_PROXY = "managed_proxy";
    private static final String KEY_UPDATE_ENABLED = "update_enabled";
    private static final String KEY_UPDATE_LAST_CHECK = "update_last_check";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 1443;
    private static final String LEGACY_RUNTIME_CONFIG = "@mtproto_worker_preconnect=1";
    private static final String DEFAULT_RUNTIME_CONFIG =
            "@connection_mode=cf_first,@mtproto_worker_preconnect=1";
    private static final String UPDATE_FEED_URL =
            "https://github.com/Regstar2/telegram-wsp/releases/latest/download/latest.json";
    private static final String UPDATE_APK_URL_PREFIX =
            "https://github.com/Regstar2/telegram-wsp/releases/download/";
    private static final long UPDATE_CHECK_INTERVAL_MS = 12L * 60L * 60L * 1000L;
    private static final int NETWORK_CONNECT_TIMEOUT_MS = 15_000;
    private static final int NETWORK_READ_TIMEOUT_MS = 30_000;
    private static final int UPDATE_METADATA_LIMIT_BYTES = 64 * 1024;
    private static final long UPDATE_APK_LIMIT_BYTES = 250L * 1024L * 1024L;
    private static final char[] HEX = "0123456789abcdef".toCharArray();

    private static boolean initialized;

    private TgWsProxyBootstrap() {
    }

    static void start(Context context) {
        synchronized (TgWsProxyBootstrap.class) {
            if (initialized) {
                return;
            }
            initialized = true;
        }

        Context appContext = context.getApplicationContext();

        Thread bootstrapThread = new Thread(
                () -> startInBackground(appContext),
                "TgWsProxyBootstrap"
        );
        bootstrapThread.setDaemon(true);
        bootstrapThread.start();

        Thread updateThread = new Thread(
                () -> checkForUpdatesInBackground(appContext),
                "TelegramWSPUpdateCheck"
        );
        updateThread.setDaemon(true);
        updateThread.start();
    }

    private static void startInBackground(Context appContext) {
        try {
            SharedPreferences integrationPrefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (!integrationPrefs.getBoolean(KEY_ENABLED, true) || !supportsArm64()) {
                disableManagedProxy(appContext, integrationPrefs);
                return;
            }

            String secret = getOrCreateSecret(integrationPrefs);
            String runtimeConfig = integrationPrefs.getString(KEY_RUNTIME_CONFIG, DEFAULT_RUNTIME_CONFIG);
            if (runtimeConfig == null || LEGACY_RUNTIME_CONFIG.equals(runtimeConfig.trim())) {
                runtimeConfig = DEFAULT_RUNTIME_CONFIG;
                integrationPrefs.edit().putString(KEY_RUNTIME_CONFIG, runtimeConfig).apply();
            }

            TgWsProxyConfig config = new TgWsProxyConfig(HOST, PORT, secret, runtimeConfig, BuildVars.LOGS_ENABLED);
            TgWsProxyOperationResult result = TgWsProxyCore.INSTANCE.start(config);
            logRuntimeState(result);

            if (!result.getSuccess()) {
                FileLog.e("TgWsProxy core start failed: " + result.getMessage());
                disableManagedProxy(appContext, integrationPrefs);
                return;
            }

            SharedPreferences telegramPrefs = appContext.getSharedPreferences("mainconfig", Context.MODE_PRIVATE);
            boolean stored = telegramPrefs.edit()
                    .putBoolean("proxy_enabled", true)
                    .putString("proxy_ip", HOST)
                    .putInt("proxy_port", PORT)
                    .putString("proxy_user", "")
                    .putString("proxy_pass", "")
                    .putString("proxy_secret", secret)
                    .commit();

            if (!stored) {
                FileLog.e("TgWsProxy could not persist Telegram proxy settings");
                TgWsProxyCore.INSTANCE.stop();
                return;
            }

            integrationPrefs.edit().putBoolean(KEY_MANAGED_PROXY, true).apply();
            applyTelegramProxy(true, secret);
        } catch (Throwable error) {
            FileLog.e("TgWsProxy bootstrap failed: " + error);
        }
    }

    private static void checkForUpdatesInBackground(Context appContext) {
        try {
            SharedPreferences preferences = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            if (!preferences.getBoolean(KEY_UPDATE_ENABLED, true)) {
                return;
            }

            long now = System.currentTimeMillis();
            long lastCheck = preferences.getLong(KEY_UPDATE_LAST_CHECK, 0L);
            if (lastCheck > 0L && now - lastCheck < UPDATE_CHECK_INTERVAL_MS) {
                return;
            }
            preferences.edit().putLong(KEY_UPDATE_LAST_CHECK, now).apply();

            String metadataJson = readSmallHttpsResource(UPDATE_FEED_URL);
            JSONObject metadata = new JSONObject(metadataJson);
            long remoteVersionCode = metadata.getLong("versionCode");
            long currentVersionCode = getCurrentVersionCode(appContext);
            if (remoteVersionCode <= currentVersionCode) {
                return;
            }

            String versionName = metadata.optString("versionName", String.valueOf(remoteVersionCode));
            String apkUrl = metadata.getString("apk");
            String apkSha256 = metadata.getString("apkSha256").toLowerCase(java.util.Locale.US);
            if (!apkUrl.startsWith(UPDATE_APK_URL_PREFIX)) {
                throw new IllegalStateException("Unexpected update APK URL: " + apkUrl);
            }
            if (!apkSha256.matches("[0-9a-f]{64}")) {
                throw new IllegalStateException("Invalid update APK SHA-256");
            }

            UpdateInfo update = new UpdateInfo(remoteVersionCode, versionName, apkUrl, apkSha256);
            offerUpdateWhenActivityReady(appContext, update, 0);
        } catch (Throwable error) {
            FileLog.e("Telegram-WSP update check failed: " + error);
        }
    }

    private static String readSmallHttpsResource(String url) throws Exception {
        HttpURLConnection connection = openHttpsConnection(url);
        try {
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IllegalStateException("Update feed HTTP status " + status);
            }

            try (InputStream input = connection.getInputStream();
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                int total = 0;
                int read;
                while ((read = input.read(buffer)) >= 0) {
                    total += read;
                    if (total > UPDATE_METADATA_LIMIT_BYTES) {
                        throw new IllegalStateException("Update metadata is too large");
                    }
                    output.write(buffer, 0, read);
                }
                return output.toString("UTF-8");
            }
        } finally {
            connection.disconnect();
        }
    }

    private static HttpURLConnection openHttpsConnection(String url) throws Exception {
        URL parsed = new URL(url);
        if (!"https".equalsIgnoreCase(parsed.getProtocol())) {
            throw new IllegalArgumentException("Only HTTPS update URLs are allowed");
        }

        HttpURLConnection connection = (HttpURLConnection) parsed.openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(NETWORK_CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(NETWORK_READ_TIMEOUT_MS);
        connection.setUseCaches(false);
        connection.setRequestProperty("Cache-Control", "no-cache");
        connection.setRequestProperty("User-Agent", "Telegram-WSP Android Updater");
        return connection;
    }

    private static long getCurrentVersionCode(Context context) throws Exception {
        PackageInfo packageInfo = context.getPackageManager().getPackageInfo(
                ApplicationLoader.getApplicationId(),
                0
        );
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return packageInfo.getLongVersionCode();
        }
        return packageInfo.versionCode;
    }

    private static void offerUpdateWhenActivityReady(
            Context appContext,
            UpdateInfo update,
            int attempt
    ) {
        Handler handler = ApplicationLoader.applicationHandler;
        if (handler == null) {
            handler = new Handler(Looper.getMainLooper());
        }

        Handler mainHandler = handler;
        mainHandler.postDelayed(() -> {
            if (LaunchActivity.instance == null) {
                if (attempt < 30) {
                    offerUpdateWhenActivityReady(appContext, update, attempt + 1);
                }
                return;
            }

            try {
                new AlertDialog.Builder(LaunchActivity.instance)
                        .setTitle(LocaleController.getString(R.string.AppUpdate))
                        .setMessage(
                                "Telegram-WSP " + update.versionName
                                        + " is available. The APK will be verified before Android asks to install it."
                        )
                        .setPositiveButton(
                                LocaleController.getString(R.string.AppUpdateNow),
                                (dialog, which) -> downloadAndInstallInBackground(appContext, update)
                        )
                        .setNegativeButton(LocaleController.getString(R.string.Cancel), null)
                        .show();
            } catch (Throwable error) {
                FileLog.e("Telegram-WSP could not show update prompt: " + error);
            }
        }, attempt == 0 ? 2500L : 1000L);
    }

    private static void downloadAndInstallInBackground(Context appContext, UpdateInfo update) {
        Toast.makeText(appContext, "Telegram-WSP: downloading update...", Toast.LENGTH_SHORT).show();

        Thread downloadThread = new Thread(() -> {
            try {
                File apk = getUpdateApkFile(appContext, update.versionCode);
                if (!isVerifiedUpdateApk(appContext, apk, update.sha256)) {
                    downloadUpdateApk(update.url, apk);
                }

                if (!isVerifiedUpdateApk(appContext, apk, update.sha256)) {
                    throw new SecurityException("Downloaded update APK did not pass verification");
                }

                Handler handler = ApplicationLoader.applicationHandler;
                if (handler == null) {
                    handler = new Handler(Looper.getMainLooper());
                }
                handler.post(() -> openUpdateInstaller(appContext, apk));
            } catch (Throwable error) {
                FileLog.e("Telegram-WSP update download failed: " + error);
                Handler handler = ApplicationLoader.applicationHandler;
                if (handler == null) {
                    handler = new Handler(Looper.getMainLooper());
                }
                handler.post(() -> Toast.makeText(
                        appContext,
                        "Telegram-WSP update failed. Try again later.",
                        Toast.LENGTH_LONG
                ).show());
            }
        }, "TelegramWSPUpdateDownload");
        downloadThread.start();
    }

    private static File getUpdateApkFile(Context context, long versionCode) {
        File directory = new File(context.getFilesDir(), "cache");
        if (!directory.exists() && !directory.mkdirs()) {
            FileLog.e("Telegram-WSP updater could not create " + directory);
        }

        File[] oldFiles = directory.listFiles((dir, name) ->
                name.startsWith("Telegram-WSP-update-") && name.endsWith(".apk"));
        if (oldFiles != null) {
            String keep = "Telegram-WSP-update-" + versionCode + ".apk";
            for (File oldFile : oldFiles) {
                if (!keep.equals(oldFile.getName())) {
                    oldFile.delete();
                }
            }
        }

        return new File(directory, "Telegram-WSP-update-" + versionCode + ".apk");
    }

    private static void downloadUpdateApk(String url, File destination) throws Exception {
        File partial = new File(destination.getAbsolutePath() + ".part");
        if (partial.exists()) {
            partial.delete();
        }

        HttpURLConnection connection = openHttpsConnection(url);
        connection.setReadTimeout(120_000);
        try {
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IllegalStateException("Update APK HTTP status " + status);
            }

            long declaredLength = connection.getContentLengthLong();
            if (declaredLength > UPDATE_APK_LIMIT_BYTES) {
                throw new IllegalStateException("Update APK exceeds size limit");
            }

            long total = 0L;
            try (InputStream input = connection.getInputStream();
                 FileOutputStream output = new FileOutputStream(partial)) {
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = input.read(buffer)) >= 0) {
                    total += read;
                    if (total > UPDATE_APK_LIMIT_BYTES) {
                        throw new IllegalStateException("Update APK exceeds size limit");
                    }
                    output.write(buffer, 0, read);
                }
                output.getFD().sync();
            }

            if (total <= 0L) {
                throw new IllegalStateException("Downloaded update APK is empty");
            }

            if (destination.exists() && !destination.delete()) {
                throw new IllegalStateException("Could not replace existing update APK");
            }
            if (!partial.renameTo(destination)) {
                throw new IllegalStateException("Could not finalize update APK");
            }
        } finally {
            connection.disconnect();
            if (partial.exists() && !destination.exists()) {
                partial.delete();
            }
        }
    }

    private static boolean isVerifiedUpdateApk(
            Context context,
            File apk,
            String expectedSha256
    ) {
        try {
            if (!apk.isFile()) {
                return false;
            }
            if (!expectedSha256.equalsIgnoreCase(sha256(apk))) {
                return false;
            }
            return hasSameSigningCertificate(context, apk);
        } catch (Throwable error) {
            FileLog.e("Telegram-WSP update verification failed: " + error);
            return false;
        }
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                digest.update(buffer, 0, read);
            }
        }

        byte[] hash = digest.digest();
        char[] chars = new char[hash.length * 2];
        for (int i = 0; i < hash.length; i++) {
            int value = hash[i] & 0xff;
            chars[i * 2] = HEX[value >>> 4];
            chars[i * 2 + 1] = HEX[value & 0x0f];
        }
        return new String(chars);
    }

    private static boolean hasSameSigningCertificate(Context context, File apk) throws Exception {
        PackageManager packageManager = context.getPackageManager();
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;

        PackageInfo installed = packageManager.getPackageInfo(
                ApplicationLoader.getApplicationId(),
                flags
        );
        PackageInfo archive = packageManager.getPackageArchiveInfo(apk.getAbsolutePath(), flags);
        if (archive == null || !ApplicationLoader.getApplicationId().equals(archive.packageName)) {
            return false;
        }

        Signature[] installedSignatures;
        Signature[] archiveSignatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (installed.signingInfo == null || archive.signingInfo == null) {
                return false;
            }
            installedSignatures = installed.signingInfo.getApkContentsSigners();
            archiveSignatures = archive.signingInfo.getApkContentsSigners();
        } else {
            installedSignatures = installed.signatures;
            archiveSignatures = archive.signatures;
        }
        return signaturesEqual(installedSignatures, archiveSignatures);
    }

    private static boolean signaturesEqual(Signature[] first, Signature[] second) {
        if (first == null || second == null || first.length != second.length) {
            return false;
        }

        Set<String> firstSet = new HashSet<>();
        Set<String> secondSet = new HashSet<>();
        for (Signature signature : first) {
            firstSet.add(signature.toCharsString());
        }
        for (Signature signature : second) {
            secondSet.add(signature.toCharsString());
        }
        return firstSet.equals(secondSet);
    }

    private static void openUpdateInstaller(Context context, File apk) {
        try {
            PackageManager packageManager = context.getPackageManager();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    && !packageManager.canRequestPackageInstalls()) {
                Intent settings = new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + ApplicationLoader.getApplicationId())
                );
                settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(settings);
                Toast.makeText(
                        context,
                        "Allow installs from Telegram-WSP, then choose Update again.",
                        Toast.LENGTH_LONG
                ).show();
                return;
            }

            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                uri = FileProvider.getUriForFile(
                        context,
                        ApplicationLoader.getApplicationId() + ".provider",
                        apk
                );
            } else {
                uri = Uri.fromFile(apk);
            }

            Intent install = new Intent(Intent.ACTION_VIEW);
            install.setDataAndType(uri, "application/vnd.android.package-archive");
            install.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            context.startActivity(install);
        } catch (Throwable error) {
            FileLog.e("Telegram-WSP could not open APK installer: " + error);
            Toast.makeText(
                    context,
                    "Telegram-WSP could not open the Android installer.",
                    Toast.LENGTH_LONG
            ).show();
        }
    }

    private static void logRuntimeState(TgWsProxyOperationResult result) {
        TgWsProxyStatus status = result.getStatus();
        if (status == null) {
            FileLog.d("TgWsProxy runtime status unavailable after start");
            return;
        }

        FileLog.d(
                "TgWsProxy runtime success=" + result.getSuccess()
                        + " state=" + status.getState()
                        + " host=" + status.getHost()
                        + " port=" + status.getPort()
                        + " outbound=" + status.getOutbound()
                        + " selected_backend=" + status.getSelectedBackend()
                        + " actual_backend=" + status.getActualBackend()
                        + " fallback_used=" + status.getFallbackUsed()
                        + " route_reason=" + status.getRouteReason()
                        + " last_error=" + status.getLastError()
        );

        Map<String, String> transport = TgWsProxyCore.INSTANCE.transportStatus();
        FileLog.d(
                "TgWsProxy transport running=" + transport.get("running")
                        + " mode=" + transport.get("mode")
                        + " active_route_kind=" + transport.get("active_route_kind")
                        + " transport_type=" + transport.get("transport_type")
                        + " last_error=" + transport.get("last_error")
        );
    }

    private static void disableManagedProxy(Context context, SharedPreferences integrationPrefs) {
        if (!integrationPrefs.getBoolean(KEY_MANAGED_PROXY, false)) {
            return;
        }

        String secret = integrationPrefs.getString(KEY_SECRET, "");
        SharedPreferences telegramPrefs = context.getSharedPreferences("mainconfig", Context.MODE_PRIVATE);
        String address = telegramPrefs.getString("proxy_ip", "");
        int port = telegramPrefs.getInt("proxy_port", 0);
        String telegramSecret = telegramPrefs.getString("proxy_secret", "");

        if (HOST.equals(address) && PORT == port && secret != null && secret.equals(telegramSecret)) {
            telegramPrefs.edit().putBoolean("proxy_enabled", false).commit();
            applyTelegramProxy(false, "");
        }
        integrationPrefs.edit().putBoolean(KEY_MANAGED_PROXY, false).apply();
    }

    private static void applyTelegramProxy(boolean enabled, String secret) {
        Runnable apply = () -> ConnectionsManager.setProxySettings(enabled, HOST, PORT, "", "", secret);
        Handler handler = ApplicationLoader.applicationHandler;
        if (handler != null) {
            handler.post(apply);
        } else {
            new Handler(Looper.getMainLooper()).post(apply);
        }
    }

    private static String getOrCreateSecret(SharedPreferences preferences) {
        String current = preferences.getString(KEY_SECRET, null);
        if (current != null && current.matches("[0-9a-fA-F]{32}")) {
            return current.toLowerCase(java.util.Locale.US);
        }

        byte[] bytes = new byte[16];
        new SecureRandom().nextBytes(bytes);
        char[] chars = new char[32];
        for (int i = 0; i < bytes.length; i++) {
            int value = bytes[i] & 0xff;
            chars[i * 2] = HEX[value >>> 4];
            chars[i * 2 + 1] = HEX[value & 0x0f];
        }
        String generated = new String(chars);
        preferences.edit().putString(KEY_SECRET, generated).commit();
        return generated;
    }

    private static boolean supportsArm64() {
        for (String abi : Build.SUPPORTED_ABIS) {
            if ("arm64-v8a".equals(abi)) {
                return true;
            }
        }
        return false;
    }

    private static final class UpdateInfo {
        final long versionCode;
        final String versionName;
        final String url;
        final String sha256;

        UpdateInfo(long versionCode, String versionName, String url, String sha256) {
            this.versionCode = versionCode;
            this.versionName = versionName;
            this.url = url;
            this.sha256 = sha256;
        }
    }
}
