package android.widget;

/*
 * Copyright (C) Contributors to the Suwayomi project
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

public class Toast {
    public static final int LENGTH_LONG = 1;
    public static final int LENGTH_SHORT = 0;

    private CharSequence text;

    private Toast(CharSequence text) {
        this.text = text;
    }

    public Toast(android.content.Context context) {
        
    }

    public void show() {
        System.out.printf("made a Toast: \"%s\"\n", text.toString());
    }

    public void cancel() {
        
    }

    public void setView(android.view.View view) {
        
    }

    public android.view.View getView() {
        return null;
    }

    public void setDuration(int duration) {
        
    }

    public int getDuration() {
        return 0;
    }

    public void setMargin(float horizontalMargin, float verticalMargin) {
        
    }

    public float getHorizontalMargin() {
        return 0;
    }

    public float getVerticalMargin() {
        return 0;
    }

    public void setGravity(int gravity, int xOffset, int yOffset) {
        
    }

    public int getGravity() {
        return 0;
    }

    public int getXOffset() {
        return 0;
    }

    public int getYOffset() {
        return 0;
    }

    public static Toast makeText(android.content.Context context, CharSequence text, int duration) {
        return new Toast(text);
    }

    public static Toast makeText(android.content.Context context, int resId, int duration) throws android.content.res.Resources.NotFoundException {
        return null;
    }

    public void setText(int resId) {
        
    }

    public void setText(CharSequence s) {
        
    }
}