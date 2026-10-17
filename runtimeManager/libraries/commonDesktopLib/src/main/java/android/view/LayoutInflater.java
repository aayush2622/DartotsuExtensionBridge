package android.view;

import android.content.Context;
import android.content.res.XmlResourceParser;
import android.widget.Checkable;
import android.widget.TextView;
import android.widget.LinearLayout;

import com.aayush262.dartotsu_extension_bridge.ui.LayoutHolder;
import com.aayush262.dartotsu_extension_bridge.ui.LayoutNode;
import com.aayush262.dartotsu_extension_bridge.ui.UiCapture;

import org.xmlpull.v1.XmlPullParser;

import java.util.Map;

/*
 * Desktop stand-in: builds a view tree from the layout trees
 * PluginResources reads out of an extension, creating the stand-in widgets.
 * Classes that aren't available here (Material, AppCompat, ...) become the
 * closest widget that is.
 */
public class LayoutInflater {
    private static final String[] PREFIXES = {"android.widget.", "android.view.", "android.webkit."};
    private static final Map<String, String> SUBSTITUTES = Map.ofEntries(
            Map.entry("SwitchCompat", "android.widget.Switch"),
            Map.entry("SwitchMaterial", "android.widget.Switch"),
            Map.entry("MaterialSwitch", "android.widget.Switch"),
            Map.entry("AppCompatCheckBox", "android.widget.CheckBox"),
            Map.entry("MaterialCheckBox", "android.widget.CheckBox"),
            Map.entry("AppCompatRadioButton", "android.widget.RadioButton"),
            Map.entry("MaterialRadioButton", "android.widget.RadioButton"),
            Map.entry("AppCompatButton", "android.widget.Button"),
            Map.entry("MaterialButton", "android.widget.Button"),
            Map.entry("AppCompatTextView", "android.widget.TextView"),
            Map.entry("MaterialTextView", "android.widget.TextView"),
            Map.entry("AppCompatEditText", "android.widget.EditText"),
            Map.entry("TextInputEditText", "android.widget.EditText"),
            Map.entry("AppCompatImageView", "android.widget.ImageView"),
            Map.entry("ShapeableImageView", "android.widget.ImageView"),
            Map.entry("ImageButton", "android.widget.ImageView"),
            Map.entry("NestedScrollView", "androidx.core.widget.NestedScrollView"),
            Map.entry("TextInputLayout", "android.widget.LinearLayout"),
            Map.entry("MaterialCardView", "android.widget.FrameLayout"),
            Map.entry("CardView", "android.widget.FrameLayout"),
            Map.entry("ConstraintLayout", "android.widget.FrameLayout"),
            Map.entry("CoordinatorLayout", "android.widget.FrameLayout"),
            Map.entry("LinearLayoutCompat", "android.widget.LinearLayout"));

    private final Context context;

    protected LayoutInflater(Context context) {
        this.context = context;
    }

    public static LayoutInflater from(Context context) {
        return new LayoutInflater(context);
    }

    public Context getContext() {
        return context;
    }

    public View inflate(int resource, ViewGroup root) {
        return inflate(resource, root, root != null);
    }

    public View inflate(int resource, ViewGroup root, boolean attachToRoot) {
        return inflate(UiCapture.resources().getLayout(resource), root, attachToRoot);
    }

    public View inflate(XmlPullParser parser, ViewGroup root) {
        return inflate(parser, root, root != null);
    }

    public View inflate(XmlPullParser parser, ViewGroup root, boolean attachToRoot) {
        if (!(parser instanceof LayoutHolder)) throw new InflateException("Not a layout of this runtime");
        View view = build(((LayoutHolder) parser).layoutNode());
        if (root != null && attachToRoot) root.addView(view);
        return view;
    }

    private View build(LayoutNode node) {
        View view = create(node.tag);
        view.bridgeAttrs.putAll(node.attrs);
        view.bridgeAttrs.put("tag", node.tag);
        Integer id = node.refs.get("id");
        if (id != null) view.setId(id);
        apply(view, node.attrs);
        if (view instanceof ViewGroup) {
            for (LayoutNode child : node.children) ((ViewGroup) view).addView(build(child));
        }
        return view;
    }

    private View create(String tag) {
        String simple = tag.substring(tag.lastIndexOf('.') + 1);
        String[] candidates = tag.indexOf('.') >= 0
                ? new String[]{tag, SUBSTITUTES.getOrDefault(simple, "")}
                : new String[]{PREFIXES[0] + tag, PREFIXES[1] + tag, PREFIXES[2] + tag, SUBSTITUTES.getOrDefault(simple, "")};
        for (String name : candidates) {
            if (name.isEmpty()) continue;
            try {
                Class<?> type = Class.forName(name);
                if (!View.class.isAssignableFrom(type)) continue;
                return (View) type.getConstructor(Context.class).newInstance(context);
            } catch (ReflectiveOperationException | LinkageError ignored) {
            }
        }
        // Unknown custom container: keep its children so nothing in it is lost.
        return new android.widget.FrameLayout(context);
    }

    private static void apply(View view, Map<String, String> attrs) {
        String text = attrs.get("text");
        if (text != null && view instanceof TextView) ((TextView) view).setText(text);
        String hint = attrs.get("hint");
        if (hint != null && view instanceof TextView) ((TextView) view).setHint(hint);
        if ("true".equals(attrs.get("checked")) && view instanceof Checkable) ((Checkable) view).setChecked(true);
        if (attrs.containsKey("clickable")) view.setClickable("true".equals(attrs.get("clickable")));
        if (attrs.containsKey("enabled")) view.setEnabled(!"false".equals(attrs.get("enabled")));
        String visibility = attrs.get("visibility");
        if (visibility != null) {
            try {
                view.setVisibility(Integer.decode(visibility));
            } catch (NumberFormatException ignored) {
            }
        }
        String description = attrs.get("contentDescription");
        if (description != null) view.setContentDescription(description);
        String orientation = attrs.get("orientation");
        if (orientation != null && view instanceof LinearLayout) {
            try {
                ((LinearLayout) view).setOrientation(Integer.decode(orientation));
            } catch (NumberFormatException ignored) {
            }
        }
    }

    public interface Factory {
        View onCreateView(String name, Context context, android.util.AttributeSet attrs);
    }

    public interface Factory2 extends Factory {
        View onCreateView(View parent, String name, Context context, android.util.AttributeSet attrs);
    }

    public interface Filter {
        boolean onLoadClass(Class clazz);
    }

    public static class InflateException extends RuntimeException {
        public InflateException(String message) {
            super(message);
        }
    }
}
