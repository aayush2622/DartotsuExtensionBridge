package android.widget;

import android.content.Context;
import android.util.AttributeSet;

/*
 * Desktop stand-in: a button with a checked state that tells its listener.
 */
public abstract class CompoundButton extends Button implements Checkable {
    public interface OnCheckedChangeListener {
        void onCheckedChanged(CompoundButton buttonView, boolean isChecked);
    }

    private boolean checked;
    private OnCheckedChangeListener listener;

    public CompoundButton(Context context) { super(context); }

    public CompoundButton(Context context, AttributeSet attrs) { super(context, attrs); }

    public CompoundButton(Context context, AttributeSet attrs, int defStyleAttr) { super(context, attrs, defStyleAttr); }

    public CompoundButton(Context context, AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
    }

    @Override
    public boolean isChecked() { return checked; }

    @Override
    public void setChecked(boolean value) {
        if (checked == value) return;
        checked = value;
        if (listener != null) listener.onCheckedChanged(this, checked);
    }

    @Override
    public void toggle() { setChecked(!checked); }

    @Override
    public boolean performClick() {
        toggle();
        super.performClick();
        return true;
    }

    public void setOnCheckedChangeListener(OnCheckedChangeListener l) { listener = l; }
}
