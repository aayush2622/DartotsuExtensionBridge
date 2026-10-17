package com.google.android.material.bottomsheet;

import android.view.View;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class BottomSheetBehavior<V extends View> {
    public static final int STATE_DRAGGING = 1;
    public static final int STATE_SETTLING = 2;
    public static final int STATE_EXPANDED = 3;
    public static final int STATE_COLLAPSED = 4;
    public static final int STATE_HIDDEN = 5;
    public static final int STATE_HALF_EXPANDED = 6;

    private int state = STATE_COLLAPSED;

    public static <V extends View> BottomSheetBehavior<V> from(V view) { return new BottomSheetBehavior<>(); }

    public int getState() { return state; }

    public void setState(int state) { this.state = state; }

    public void setPeekHeight(int peekHeight) {}

    public void setSkipCollapsed(boolean skipCollapsed) {}

    public void setDraggable(boolean draggable) {}

    public void setHideable(boolean hideable) {}

    public void setMaxWidth(int maxWidth) {}
}
