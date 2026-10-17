package com.google.android.material.bottomsheet;

import androidx.fragment.app.DialogFragment;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class BottomSheetDialogFragment extends DialogFragment {
    public BottomSheetDialogFragment() {}
}
