package org.telegram.messenger;

import android.app.Activity;
import android.app.Application;
import android.content.res.Configuration;
import android.os.Build;
import android.os.Bundle;
import android.view.View;

import org.telegram.ui.ActionBar.Theme;

/**
 * Xiaomi/MIUI/HyperOS compatibility for Telegram's native dark theme.
 *
 * This does NOT force light mode and does NOT change Android uiMode. Telegram keeps following
 * the system through its own AUTO_NIGHT_TYPE_SYSTEM logic. The only purpose of this class is
 * to prevent Xiaomi/Android Force Dark from applying a second algorithmic inversion on top of
 * Telegram's already-rendered light/dark UI.
 */
final class TelegramWspDarkModeCompat {

    private static boolean installed;

    private TelegramWspDarkModeCompat() {
    }

    static void install(Application application) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return;
        }

        synchronized (TelegramWspDarkModeCompat.class) {
            if (installed) {
                return;
            }
            installed = true;
        }

        application.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityPreCreated(Activity activity, Bundle savedInstanceState) {
                protectNativeTheme(activity);
            }

            @Override
            public void onActivityCreated(Activity activity, Bundle savedInstanceState) {
                protectNativeTheme(activity);
            }

            @Override
            public void onActivityResumed(Activity activity) {
                protectNativeTheme(activity);
                logThemeState(activity);
            }

            @Override
            public void onActivityStarted(Activity activity) {
            }

            @Override
            public void onActivityPaused(Activity activity) {
            }

            @Override
            public void onActivityStopped(Activity activity) {
            }

            @Override
            public void onActivitySaveInstanceState(Activity activity, Bundle outState) {
            }

            @Override
            public void onActivityDestroyed(Activity activity) {
            }
        });
    }

    private static void protectNativeTheme(Activity activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || activity == null || activity.getWindow() == null) {
            return;
        }

        View decorView = activity.getWindow().getDecorView();
        if (decorView != null) {
            decorView.setForceDarkAllowed(false);
        }
    }

    private static void logThemeState(Activity activity) {
        if (!BuildVars.LOGS_ENABLED || activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return;
        }

        try {
            int systemNightMode =
                    activity.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
            boolean systemNight = systemNightMode == Configuration.UI_MODE_NIGHT_YES;
            boolean telegramThemeDark = Theme.getActiveTheme() != null && Theme.isCurrentThemeDark();

            FileLog.d(
                    "Telegram-WSP dark mode systemNight=" + systemNight
                            + " autoNightType=" + Theme.selectedAutoNightType
                            + " telegramThemeDark=" + telegramThemeDark
                            + " forceDarkAllowed=" + activity.getWindow().getDecorView().isForceDarkAllowed()
            );
        } catch (Throwable error) {
            FileLog.e("Telegram-WSP dark-mode diagnostics failed: " + error);
        }
    }
}
