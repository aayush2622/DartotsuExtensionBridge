package androidx.fragment.app;

import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class Fragment {
    /**
     * The context fragments report as attached to (the app's), set by the
     * backend. Null until then, and [requireContext] throws as on Android.
     */
    public static Context hostContext;

    private Bundle arguments;
    private String tag;
    private final FragmentManager childFragmentManager = new FragmentManager();

    private View view;
    private LayoutInflater inflater;
    FragmentManager parentManager;

    public Fragment() {}

    /** Called by the bridge's UI capture once it has built the fragment's screen. */
    public void attachInflater(LayoutInflater inflater) { this.inflater = inflater; }

    public void attachView(View view) { this.view = view; }

    void setTag(String tag) { this.tag = tag; }

    public String getTag() { return tag; }

    public Bundle getArguments() { return arguments; }

    public void setArguments(Bundle args) { arguments = args; }

    public Bundle requireArguments() {
        if (arguments == null) throw new IllegalStateException("Fragment " + this + " does not have any arguments.");
        return arguments;
    }

    public Context getContext() { return hostContext; }

    public Context requireContext() {
        if (hostContext == null) throw new IllegalStateException("Fragment " + this + " not attached to a context.");
        return hostContext;
    }

    public FragmentActivity getActivity() { return null; }

    public FragmentActivity requireActivity() {
        throw new IllegalStateException("Fragment " + this + " not attached to an activity.");
    }

    public Resources getResources() { return requireContext().getResources(); }

    public final String getString(int resId) { return getResources().getString(resId); }

    public Fragment getParentFragment() { return null; }

    public FragmentManager getParentFragmentManager() {
        return parentManager != null ? parentManager : new FragmentManager();
    }

    public FragmentManager getChildFragmentManager() { return childFragmentManager; }

    public LayoutInflater getLayoutInflater() { return inflater; }

    public View getView() { return view; }

    public View requireView() {
        if (view != null) return view;
        throw new IllegalStateException("Fragment " + this + " did not return a View from onCreateView() or this was called before onCreateView().");
    }

    public boolean isAdded() { return view != null; }

    public boolean isVisible() { return false; }

    public boolean isDetached() { return true; }

    public void startActivity(Intent intent) {}

    public void onCreate(Bundle savedInstanceState) {}

    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) { return null; }

    public void onViewCreated(View view, Bundle savedInstanceState) {}

    public void onStart() {}

    public void onResume() {}

    public void onPause() {}

    public void onStop() {}

    public void onDestroyView() {}

    public void onDestroy() {}

    public void onDetach() {}

    public void onConfigurationChanged(Configuration newConfig) {}
}
