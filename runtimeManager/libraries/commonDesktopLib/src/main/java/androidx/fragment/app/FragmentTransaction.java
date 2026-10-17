package androidx.fragment.app;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class FragmentTransaction {
    public FragmentTransaction add(Fragment fragment, String tag) { return this; }

    public FragmentTransaction add(int containerViewId, Fragment fragment) { return this; }

    public FragmentTransaction add(int containerViewId, Fragment fragment, String tag) { return this; }

    public FragmentTransaction replace(int containerViewId, Fragment fragment) { return this; }

    public FragmentTransaction replace(int containerViewId, Fragment fragment, String tag) { return this; }

    public FragmentTransaction remove(Fragment fragment) { return this; }

    public FragmentTransaction attach(Fragment fragment) { return this; }

    public FragmentTransaction detach(Fragment fragment) { return this; }

    public FragmentTransaction show(Fragment fragment) { return this; }

    public FragmentTransaction hide(Fragment fragment) { return this; }

    public FragmentTransaction addToBackStack(String name) { return this; }

    public FragmentTransaction setReorderingAllowed(boolean reorderingAllowed) { return this; }

    public FragmentTransaction setTransition(int transit) { return this; }

    public FragmentTransaction setCustomAnimations(int enter, int exit) { return this; }

    public FragmentTransaction setCustomAnimations(int enter, int exit, int popEnter, int popExit) { return this; }

    public int commit() { return -1; }

    public int commitAllowingStateLoss() { return -1; }

    public void commitNow() {}

    public void commitNowAllowingStateLoss() {}
}
