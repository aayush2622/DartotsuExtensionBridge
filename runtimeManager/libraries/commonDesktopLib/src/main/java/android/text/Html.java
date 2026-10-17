package android.text;


import android.graphics.drawable.Drawable;
import org.jetbrains.annotations.NotNull;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.parser.Parser;
import org.jsoup.safety.Safelist;
import org.xml.sax.XMLReader;

/**
 * Project: TachiServer
 * Author: nulldev
 * Creation Date: 16/08/16
 *
 * Android compat class for processing HTML
 */

public class Html {

    public static final int FROM_HTML_MODE_LEGACY = 0;
    public static final int FROM_HTML_MODE_COMPACT = 63;
    public static final int TO_HTML_PARAGRAPH_LINES_CONSECUTIVE = 0;
    public static final int TO_HTML_PARAGRAPH_LINES_INDIVIDUAL = 1;

    public static Spanned fromHtml(String source) {
        return new FakeSpanned(toText(source));
    }

    public static Spanned fromHtml(String source, int flags) {
        return fromHtml(source);
    }

    public static Spanned fromHtml(String source, ImageGetter imageGetter, TagHandler tagHandler) {
        return fromHtml(source);
    }

    public static Spanned fromHtml(String source, int flags, ImageGetter imageGetter, TagHandler tagHandler) {
        return fromHtml(source);
    }

    private static String toText(String source) {
        if (source == null) return "";
        String marked = source
                .replaceAll("(?i)<br\\s*/?>", "\uE000")
                .replaceAll("(?i)</(p|div|h[1-6]|li)>", "\uE000\uE000");
        String text = Parser.unescapeEntities(Jsoup.clean(marked, "", Safelist.none(), OUTPUT), false);
        return text.replaceAll("\\s+", " ").replace("\uE000 ", "\uE000").replace(" \uE000", "\uE000")
                .replaceAll("\uE000{3,}", "\uE000\uE000").replace('\uE000', '\n').trim();
    }

    private static final Document.OutputSettings OUTPUT = new Document.OutputSettings().prettyPrint(false);

    public static String toHtml(Spanned text) {
        return text.toString();
    }

    /** From: http://stackoverflow.com/a/25228492/5054192 **/
    public static String escapeHtml(CharSequence s) {
        StringBuilder out = new StringBuilder(Math.max(16, s.length()));
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c > 127 || c == '"' || c == '<' || c == '>' || c == '&') {
                out.append("&#");
                out.append((int) c);
                out.append(';');
            } else {
                out.append(c);
            }
        }
        return out.toString();
    }

    public interface TagHandler {
        void handleTag(boolean var1, String var2, Editable var3, XMLReader var4);
    }

    public interface ImageGetter {
        Drawable getDrawable(String var1);
    }

    private static class FakeSpanned implements Spanned {

        String string;

        public FakeSpanned(String string) {
            this.string = string;
        }

        @Override
        @SuppressWarnings("unchecked")
        public <T> T[] getSpans(int i, int i1, Class<T> aClass) {
            return (T[]) java.lang.reflect.Array.newInstance(aClass, 0);
        }

        @Override
        public int getSpanStart(Object o) {
            return 0;
        }

        @Override
        public int getSpanEnd(Object o) {
            return 0;
        }

        @Override
        public int getSpanFlags(Object o) {
            return 0;
        }

        @Override
        public int nextSpanTransition(int i, int i1, Class aClass) {
            return i1;
        }

        @Override
        public int length() {
            return string.length();
        }

        @Override
        public char charAt(int index) {
            return string.charAt(index);
        }

        @Override
        public CharSequence subSequence(int start, int end) {
            return string.subSequence(start, end);
        }

        @NotNull
        @Override
        public String toString() {
            return string;
        }
    }
}
