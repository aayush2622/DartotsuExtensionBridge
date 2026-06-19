package androidx.preference;

import android.content.Context;

import androidx.annotation.NonNull;

public class PreferenceGroup extends Preference {
     public PreferenceGroup(Context context) {
         super(context);
     }

    public int getPreferenceCount() {
        throw new UnsupportedOperationException("Not implemented");
    }
    @NonNull
    public Preference getPreference(int index) {
        throw new UnsupportedOperationException("Not implemented");
    }

}
