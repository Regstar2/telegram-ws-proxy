package org.telegram.messenger;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import org.telegram.tgnet.ConnectionsManager;

import java.security.SecureRandom;

import io.github.regstar2.tgwsproxy.core.TgWsProxyConfig;
import io.github.regstar2.tgwsproxy.core.TgWsProxyCore;
import io.github.regstar2.tgwsproxy.core.TgWsProxyOperationResult;

final class TgWsProxyBootstrap {
    private static final String PREFS = "tgwsproxy";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_SECRET = "secret";
    private static final String KEY_RUNTIME_CONFIG = "runtime_config";
    private static final String KEY_MANAGED_PROXY = "managed_proxy";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 1443;
    private static final String DEFAULT_RUNTIME_CONFIG = "@mtproto_worker_preconnect=1";
    private static final char[] HEX = "0123456789abcdef".toCharArray();

    private static boolean initialized;

    private TgWsProxyBootstrap() {
    }

    static synchronized void start(Context context) {
        if (initialized) {
            return;
        }
        initialized = true;

        Context appContext = context.getApplicationContext();
        SharedPreferences integrationPrefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (!integrationPrefs.getBoolean(KEY_ENABLED, true) || !supportsArm64()) {
            disableManagedProxy(appContext, integrationPrefs);
            return;
        }

        String secret = getOrCreateSecret(integrationPrefs);
        String runtimeConfig = integrationPrefs.getString(KEY_RUNTIME_CONFIG, DEFAULT_RUNTIME_CONFIG);
        if (runtimeConfig == null) {
            runtimeConfig = DEFAULT_RUNTIME_CONFIG;
        }

        TgWsProxyConfig config = new TgWsProxyConfig(HOST, PORT, secret, runtimeConfig, BuildVars.LOGS_ENABLED);
        TgWsProxyOperationResult result = TgWsProxyCore.INSTANCE.start(config);
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
        if (ApplicationLoader.applicationHandler != null) {
            ApplicationLoader.applicationHandler.postDelayed(apply, 500);
        } else {
            apply.run();
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
}
