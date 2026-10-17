package androidx.fragment.app;

import android.os.Bundle;
import android.view.View;

import java.util.Collections;
import java.util.List;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class FragmentManager {
    public FragmentManager() {}

    public FragmentTransaction beginTransaction() { return new FragmentTransaction(); }

    public boolean executePendingTransactions() { return false; }

    public Fragment findFragmentById(int id) { return null; }

    public Fragment findFragmentByTag(String tag) { return null; }

    public List<Fragment> getFragments() { return Collections.emptyList(); }

    public int getBackStackEntryCount() { return 0; }

    public void popBackStack() {}

    public boolean popBackStackImmediate() { return false; }

    public boolean isDestroyed() { return false; }

    public boolean isStateSaved() { return false; }

    public void registerFragmentLifecycleCallbacks(FragmentLifecycleCallbacks callbacks, boolean recursive) {}

    public void unregisterFragmentLifecycleCallbacks(FragmentLifecycleCallbacks callbacks) {}

    public abstract static class FragmentLifecycleCallbacks {
        public void onFragmentCreated(FragmentManager fm, Fragment f, Bundle savedInstanceState) {}

        public void onFragmentViewCreated(FragmentManager fm, Fragment f, View v, Bundle savedInstanceState) {}

        public void onFragmentStarted(FragmentManager fm, Fragment f) {}

        public void onFragmentResumed(FragmentManager fm, Fragment f) {}

        public void onFragmentPaused(FragmentManager fm, Fragment f) {}

        public void onFragmentStopped(FragmentManager fm, Fragment f) {}

        public void onFragmentViewDestroyed(FragmentManager fm, Fragment f) {}

        public void onFragmentDestroyed(FragmentManager fm, Fragment f) {}
    }
}
