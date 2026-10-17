package androidx.preference;

import android.content.Context;
import android.content.SharedPreferences;

public class PreferenceManager {
    private final Context context;
    private String sharedPreferencesName;
    private int sharedPreferencesMode = Context.MODE_PRIVATE;

    public PreferenceManager(Context context) { this.context = context; }

    public static SharedPreferences getDefaultSharedPreferences(Context context) {
        return android.preference.PreferenceManager.getDefaultSharedPreferences(context);
    }

    public PreferenceScreen createPreferenceScreen(Context context) { return new PreferenceScreen(context); }

    public String getSharedPreferencesName() { return sharedPreferencesName; }

    public void setSharedPreferencesName(String name) { sharedPreferencesName = name; }

    public int getSharedPreferencesMode() { return sharedPreferencesMode; }

    public void setSharedPreferencesMode(int mode) { sharedPreferencesMode = mode; }

    public SharedPreferences getSharedPreferences() {
        return sharedPreferencesName == null
                ? getDefaultSharedPreferences(context)
                : context.getSharedPreferences(sharedPreferencesName, sharedPreferencesMode);
    }
}
