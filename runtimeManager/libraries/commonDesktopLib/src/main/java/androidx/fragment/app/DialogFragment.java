package androidx.fragment.app;

import android.app.Dialog;
import android.content.DialogInterface;
import android.os.Bundle;

import com.aayush262.dartotsu_extension_bridge.prefs.PreferenceRecorder;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class DialogFragment extends Fragment implements DialogInterface.OnCancelListener, DialogInterface.OnDismissListener {
    public static final int STYLE_NORMAL = 0;
    public static final int STYLE_NO_TITLE = 1;
    public static final int STYLE_NO_FRAME = 2;
    public static final int STYLE_NO_INPUT = 3;

    private int theme;

    public DialogFragment() {}

    public void show(FragmentManager manager, String tag) { setTag(tag); build(); }

    public void showNow(FragmentManager manager, String tag) { setTag(tag); build(); }

    public int show(FragmentTransaction transaction, String tag) { setTag(tag); build(); return -1; }

    /**
     * While the bridge probes an extension's settings screen
     * ({@link PreferenceRecorder}), runs the creation callbacks so the
     * preferences they read are recorded. Views aren't available, so they
     * usually stop partway; that is expected.
     */
    private void build() {
        if (!PreferenceRecorder.isBuildingSettings()) return;
        try { onCreate(null); } catch (Throwable ignored) {}
        try { onCreateDialog(null); } catch (Throwable ignored) {}
        try { onViewCreated(null, null); } catch (Throwable ignored) {}
    }

    public void dismiss() {}

    public void dismissAllowingStateLoss() {}

    public void dismissNow() {}

    public Dialog getDialog() { return null; }

    public Dialog requireDialog() {
        throw new IllegalStateException("DialogFragment " + this + " does not have a Dialog.");
    }

    public Dialog onCreateDialog(Bundle savedInstanceState) { return null; }

    public void setStyle(int style, int theme) { this.theme = theme; }

    public int getTheme() { return theme; }

    public void setCancelable(boolean cancelable) {}

    public boolean isCancelable() { return true; }

    @Override
    public void onCancel(DialogInterface dialog) {}

    @Override
    public void onDismiss(DialogInterface dialog) {}
}
