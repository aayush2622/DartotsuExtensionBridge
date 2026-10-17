package androidx.preference;

import android.content.Context;

import java.util.ArrayList;
import java.util.List;

/** Children are shown inline on the screen the category is added to. */
public class PreferenceCategory extends PreferenceGroup {
    private final List<Preference> pending = new ArrayList<>();
    private PreferenceScreen screen;

    public PreferenceCategory(Context context) {
        super(context);
    }

    public boolean addPreference(Preference preference) {
        if (screen != null) return screen.addPreference(preference);
        pending.add(preference);
        return true;
    }

    void attachTo(PreferenceScreen screen) {
        this.screen = screen;
        for (Preference preference : pending) screen.addPreference(preference);
        pending.clear();
    }
}
