package com.google.android.material.bottomsheet;

import android.app.Dialog;
import android.content.Context;
import android.widget.FrameLayout;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class BottomSheetDialog extends Dialog {
    private final BottomSheetBehavior<FrameLayout> behavior = new BottomSheetBehavior<>();

    public BottomSheetDialog(Context context) { super(context); }

    public BottomSheetDialog(Context context, int theme) { super(context, theme); }

    public BottomSheetBehavior<FrameLayout> getBehavior() { return behavior; }

    public void setDismissWithAnimation(boolean dismissWithAnimation) {}
}
