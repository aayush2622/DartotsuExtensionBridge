package androidx.fragment.app;

import android.app.Dialog;
import android.content.DialogInterface;
import android.os.Bundle;

import com.aayush262.dartotsu_extension_bridge.ui.UiCapture;

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

    public void show(FragmentManager manager, String tag) { open(manager, tag); }

    public void showNow(FragmentManager manager, String tag) { open(manager, tag); }

    public int show(FragmentTransaction transaction, String tag) { open(null, tag); return -1; }

    /** While the bridge captures a settings screen, hands this fragment over to be built. */
    private void open(FragmentManager manager, String tag) {
        setTag(tag);
        parentManager = manager;
        UiCapture.shown(this);
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
