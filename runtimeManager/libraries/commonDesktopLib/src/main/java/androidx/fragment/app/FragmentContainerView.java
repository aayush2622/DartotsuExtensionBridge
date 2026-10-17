package androidx.fragment.app;

import android.content.Context;
import android.widget.FrameLayout;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class FragmentContainerView extends FrameLayout {
    public FragmentContainerView(Context context) { super(context); }
}
