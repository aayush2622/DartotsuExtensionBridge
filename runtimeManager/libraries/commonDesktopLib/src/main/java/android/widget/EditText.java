package android.widget;

import android.content.Context;
import android.text.Editable;
import android.text.SpannableStringBuilder;
import android.util.AttributeSet;

/*
 * Desktop stand-in: text that can be read back and set, like the real one.
 */
public class EditText extends TextView {
    public EditText(Context context) { super(context); }

    public EditText(Context context, AttributeSet attrs) { super(context, attrs); }

    public EditText(Context context, AttributeSet attrs, int defStyleAttr) { super(context, attrs, defStyleAttr); }

    public EditText(Context context, AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
    }

    @Override
    protected CharSequence storeText(CharSequence value) {
        return new SpannableStringBuilder(value == null ? "" : value);
    }

    @Override
    public Editable getText() {
        CharSequence current = super.getText();
        return current instanceof Editable ? (Editable) current : new SpannableStringBuilder(current);
    }

    public void setSelection(int index) {}

    public void setSelection(int start, int stop) {}

    public void selectAll() {}
}
