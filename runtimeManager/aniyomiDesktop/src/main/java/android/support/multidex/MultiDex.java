package android.support.multidex;

import android.content.Context;

import com.aayush262.dartotsu_extension_bridge.LogLevel;
import com.aayush262.dartotsu_extension_bridge.Logger;

/**
 * MultiDex that does nothing.
 */
public class MultiDex {

    public static void install(Context context) {
        Logger.log("Ignoring MultiDex installation attempt for app: {}"+ context.getPackageName(), LogLevel.DEBUG);
    }
}
