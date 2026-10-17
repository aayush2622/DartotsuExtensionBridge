package android.widget;

import android.content.Context;
import android.util.AttributeSet;
import android.view.ViewParent;

/* Desktop stand-in: checking one unchecks the rest of its RadioGroup. */
public class RadioButton extends CompoundButton {
    public RadioButton(Context context) { super(context); }

    public RadioButton(Context context, AttributeSet attrs) { super(context, attrs); }

    public RadioButton(Context context, AttributeSet attrs, int defStyleAttr) { super(context, attrs, defStyleAttr); }

    public RadioButton(Context context, AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
    }

    @Override
    public void toggle() {
        if (!isChecked()) setChecked(true);
    }

    @Override
    public void setChecked(boolean value) {
        super.setChecked(value);
        ViewParent parent = getParent();
        if (value && parent instanceof RadioGroup) ((RadioGroup) parent).childChecked(this);
    }
}
