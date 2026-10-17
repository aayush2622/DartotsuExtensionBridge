package android.widget;

import android.content.Context;
import android.text.Editable;
import android.text.SpannableStringBuilder;
import android.text.TextWatcher;
import android.util.AttributeSet;
import android.view.View;

import com.aayush262.dartotsu_extension_bridge.ui.UiCapture;

import java.util.ArrayList;
import java.util.List;

/*
 * Desktop stand-in: remembers its text, hint and watchers so a screen can be
 * read and driven; nothing is measured or drawn.
 */
public class TextView extends View {
    public enum BufferType { NORMAL, SPANNABLE, EDITABLE }

    private CharSequence text = "";
    private CharSequence hint;
    private final List<TextWatcher> watchers = new ArrayList<>();

    public TextView(Context context) { super(context); }

    public TextView(Context context, AttributeSet attrs) { super(context, attrs); }

    public TextView(Context context, AttributeSet attrs, int defStyleAttr) { super(context, attrs, defStyleAttr); }

    public TextView(Context context, AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
    }

    /** What the view stores for [value]; an EditText keeps an editable copy. */
    protected CharSequence storeText(CharSequence value) {
        return value == null ? "" : value;
    }

    public CharSequence getText() { return text; }

    public final void setText(CharSequence value) { setText(value, BufferType.NORMAL); }

    public void setText(CharSequence value, BufferType type) {
        CharSequence before = text;
        text = storeText(value);
        if (watchers.isEmpty()) return;
        for (TextWatcher w : new ArrayList<>(watchers)) w.beforeTextChanged(before, 0, before.length(), text.length());
        for (TextWatcher w : new ArrayList<>(watchers)) w.onTextChanged(text, 0, before.length(), text.length());
        Editable after = text instanceof Editable ? (Editable) text : new SpannableStringBuilder(text);
        for (TextWatcher w : new ArrayList<>(watchers)) w.afterTextChanged(after);
    }

    public final void setText(int resid) { setText(UiCapture.resources().getText(resid)); }

    public int length() { return text.length(); }

    public CharSequence getHint() { return hint; }

    public final void setHint(CharSequence value) { hint = value; }

    public final void setHint(int resid) { hint = UiCapture.resources().getText(resid); }

    public void addTextChangedListener(TextWatcher watcher) { watchers.add(watcher); }

    public void removeTextChangedListener(TextWatcher watcher) { watchers.remove(watcher); }
}
