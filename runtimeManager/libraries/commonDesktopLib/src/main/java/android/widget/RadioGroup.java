package android.widget;

import android.content.Context;
import android.util.AttributeSet;
import android.view.View;
import android.view.ViewGroup;

/* Desktop stand-in: tracks which RadioButton child is checked. */
public class RadioGroup extends LinearLayout {
    public interface OnCheckedChangeListener {
        void onCheckedChanged(RadioGroup group, int checkedId);
    }

    private int checkedId = -1;
    private boolean updating;
    private OnCheckedChangeListener listener;

    public RadioGroup(Context context) { super(context); }

    public RadioGroup(Context context, AttributeSet attrs) { super(context, attrs); }

    void childChecked(RadioButton button) {
        if (updating) return;
        updating = true;
        try {
            for (int i = 0; i < getChildCount(); i++) {
                View child = getChildAt(i);
                if (child != button && child instanceof RadioButton) ((RadioButton) child).setChecked(false);
            }
        } finally {
            updating = false;
        }
        checkedId = button.getId();
        if (listener != null) listener.onCheckedChanged(this, checkedId);
    }

    public void check(int id) {
        View child = findViewById(id);
        if (child instanceof RadioButton) ((RadioButton) child).setChecked(true);
    }

    public void clearCheck() {
        for (int i = 0; i < getChildCount(); i++) {
            View child = getChildAt(i);
            if (child instanceof RadioButton) ((RadioButton) child).setChecked(false);
        }
        checkedId = -1;
    }

    public int getCheckedRadioButtonId() { return checkedId; }

    public void setOnCheckedChangeListener(OnCheckedChangeListener l) { listener = l; }
}
