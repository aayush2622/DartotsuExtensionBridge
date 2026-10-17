package android.text;

import java.util.ArrayList;
import java.util.List;

/*
 * Desktop stand-in: keeps the characters and the spans handed to it, which is
 * all a settings screen needs from styled text.
 */
public class SpannableStringBuilder implements CharSequence, GetChars, Spannable, Editable, Appendable {
    private final StringBuilder text = new StringBuilder();
    private final List<Object[]> spans = new ArrayList<>();
    private InputFilter[] filters = new InputFilter[0];

    public SpannableStringBuilder() {}

    public SpannableStringBuilder(CharSequence source) {
        text.append(source);
    }

    public SpannableStringBuilder(CharSequence source, int start, int end) {
        text.append(source, start, end);
    }

    @Override public int length() { return text.length(); }

    @Override public char charAt(int index) { return text.charAt(index); }

    @Override public CharSequence subSequence(int start, int end) { return new SpannableStringBuilder(text, start, end); }

    @Override public String toString() { return text.toString(); }

    @Override public void getChars(int start, int end, char[] dest, int destoff) { text.getChars(start, end, dest, destoff); }

    @Override public Editable replace(int start, int end, CharSequence tb, int tbstart, int tbend) {
        text.replace(start, end, tb.subSequence(tbstart, tbend).toString());
        return this;
    }

    @Override public Editable replace(int start, int end, CharSequence tb) {
        text.replace(start, end, tb.toString());
        return this;
    }

    @Override public Editable insert(int where, CharSequence tb, int start, int end) {
        text.insert(where, tb.subSequence(start, end));
        return this;
    }

    @Override public Editable insert(int where, CharSequence tb) {
        text.insert(where, tb);
        return this;
    }

    @Override public Editable delete(int start, int end) {
        text.delete(start, end);
        return this;
    }

    @Override public Editable append(CharSequence tb) {
        text.append(tb);
        return this;
    }

    @Override public Editable append(CharSequence tb, int start, int end) {
        text.append(tb, start, end);
        return this;
    }

    @Override public Editable append(char c) {
        text.append(c);
        return this;
    }

    @Override public void clear() { text.setLength(0); spans.clear(); }

    @Override public void clearSpans() { spans.clear(); }

    @Override public void setFilters(InputFilter[] filters) { this.filters = filters; }

    @Override public InputFilter[] getFilters() { return filters; }

    @Override public void setSpan(Object what, int start, int end, int flags) {
        removeSpan(what);
        spans.add(new Object[]{what, start, end, flags});
    }

    @Override public void removeSpan(Object what) { spans.removeIf(s -> s[0] == what); }

    @Override @SuppressWarnings("unchecked")
    public <T> T[] getSpans(int start, int end, Class<T> type) {
        List<T> found = new ArrayList<>();
        for (Object[] s : spans) {
            if (type == null || type.isInstance(s[0])) found.add((T) s[0]);
        }
        return found.toArray((T[]) java.lang.reflect.Array.newInstance(type == null ? Object.class : type, 0));
    }

    @Override public int getSpanStart(Object tag) { for (Object[] s : spans) if (s[0] == tag) return (Integer) s[1]; return -1; }

    @Override public int getSpanEnd(Object tag) { for (Object[] s : spans) if (s[0] == tag) return (Integer) s[2]; return -1; }

    @Override public int getSpanFlags(Object tag) { for (Object[] s : spans) if (s[0] == tag) return (Integer) s[3]; return 0; }

    @Override public int nextSpanTransition(int start, int limit, Class type) { return limit; }
}
