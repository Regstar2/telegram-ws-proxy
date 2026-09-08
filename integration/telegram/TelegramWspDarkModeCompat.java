package org.telegram.messenger;

import android.app.Activity;
import android.app.Application;
import android.os.Build;
import android.os.Bundle;
import android.view.View;

/**
 * Keeps Xiaomi/MIUI/HyperOS global Force Dark from algorithmically inverting Telegram UI.
 *
 * Telegram already manages its own light/dark themes and upstream styles opt out through
 * android:forceDarkAllowed=false. Some Xiaomi ROMs still apply vendor-level inversion to
 * fork package IDs, so we reinforce the opt-out directly on each Activity DecorView.
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
                disableForceDark(activity);
            }

            @Override
            public void onActivityCreated(Activity activity, Bundle savedInstanceState) {
                disableForceDark(activity);
            }

            @Override
            public void onActivityResumed(Activity activity) {
                disableForceDark(activity);
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

    private static void disableForceDark(Activity activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || activity == null || activity.getWindow() == null) {
            return;
        }

        View decorView = activity.getWindow().getDecorView();
        if (decorView != null) {
            decorView.setForceDarkAllowed(false);
        }
    }
}
