package com.aayush262.dartotsu_extension_bridge.ui;

import android.content.res.Configuration;
import android.content.res.Resources;
import android.content.res.XmlResourceParser;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.util.DisplayMetrics;

import net.dongliu.apk.parser.parser.BinaryXmlParser;
import net.dongliu.apk.parser.parser.ResourceTableParser;
import net.dongliu.apk.parser.parser.XmlStreamer;
import net.dongliu.apk.parser.struct.ResourceValue;
import net.dongliu.apk.parser.struct.resource.ResourceEntry;
import net.dongliu.apk.parser.struct.resource.ResourcePackage;
import net.dongliu.apk.parser.struct.resource.ResourceTable;
import net.dongliu.apk.parser.struct.resource.Type;
import net.dongliu.apk.parser.struct.xml.Attribute;
import net.dongliu.apk.parser.struct.xml.XmlCData;
import net.dongliu.apk.parser.struct.xml.XmlNamespaceEndTag;
import net.dongliu.apk.parser.struct.xml.XmlNamespaceStartTag;
import net.dongliu.apk.parser.struct.xml.XmlNodeEndTag;
import net.dongliu.apk.parser.struct.xml.XmlNodeStartTag;

import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Proxy;
import java.nio.ByteBuffer;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * An extension's own resources, read from the `resources.arsc` and `res/`
 * entries the loader keeps in its converted jar. Enough of [Resources] for
 * settings screens: ids by name, strings, and layouts as {@link LayoutNode}
 * trees. Drawables and colours are placeholders; nothing here draws.
 */
public class PluginResources extends Resources {
    private static final short APP_PACKAGE = 0x7f;
    private static final DisplayMetrics METRICS = new DisplayMetrics();

    static {
        METRICS.density = 1f;
        METRICS.scaledDensity = 1f;
        METRICS.densityDpi = 160;
        METRICS.widthPixels = 1080;
        METRICS.heightPixels = 1920;
    }

    private final ClassLoader loader;
    private final ResourceTable table;
    private final Map<String, Integer> idsByName = new HashMap<>();
    private final Map<Integer, String> typeById = new HashMap<>();
    private final Map<Integer, String> nameById = new HashMap<>();
    private final Map<Integer, ResourceEntry> entryById = new HashMap<>();

    public PluginResources(ClassLoader loader) throws IOException {
        super(null, null, null);
        this.loader = loader;
        try (InputStream in = open("resources.arsc")) {
            if (in == null) {
                table = null;
                return;
            }
            ResourceTableParser parser = new ResourceTableParser(ByteBuffer.wrap(in.readAllBytes()));
            parser.parse();
            table = parser.getResourceTable();
        }
        ResourcePackage pkg = table.getPackage(APP_PACKAGE);
        if (pkg == null) return;
        for (Map.Entry<Short, java.util.List<Type>> types : pkg.getTypesMap().entrySet()) {
            for (Type type : types.getValue()) {
                long[] offsets = type.getOffsets();
                for (int i = 0; offsets != null && i < offsets.length; i++) {
                    ResourceEntry entry = type.getResourceEntry(i);
                    if (entry == null || entry.getKey() == null) continue;
                    int id = (APP_PACKAGE << 24) | (types.getKey() << 16) | i;
                    idsByName.putIfAbsent(type.getName() + "/" + entry.getKey(), id);
                    typeById.putIfAbsent(id, type.getName());
                    nameById.putIfAbsent(id, entry.getKey());
                    entryById.putIfAbsent(id, entry);
                }
            }
        }
    }

    /**
     * The extension's own file, not a same-named one the bridge itself carries
     * (the class loader asks its parent first).
     */
    private InputStream open(String name) throws IOException {
        java.net.URL url = loader instanceof java.net.URLClassLoader
                ? ((java.net.URLClassLoader) loader).findResource(name)
                : loader.getResource(name);
        return url == null ? null : url.openStream();
    }

    @Override
    public int getIdentifier(String name, String defType, String defPackage) {
        if (name == null) return 0;
        String type = defType;
        String entry = name;
        int colon = entry.indexOf(':');
        if (colon >= 0) entry = entry.substring(colon + 1);
        int slash = entry.indexOf('/');
        if (slash >= 0) {
            type = entry.substring(0, slash);
            entry = entry.substring(slash + 1);
        }
        Integer id = idsByName.get(type + "/" + entry);
        return id == null ? 0 : id;
    }

    @Override
    public String getResourceName(int id) {
        return nameById.containsKey(id) ? "app:" + typeById.get(id) + "/" + nameById.get(id) : null;
    }

    @Override
    public String getResourceEntryName(int id) {
        return nameById.get(id);
    }

    @Override
    public String getResourceTypeName(int id) {
        return typeById.get(id);
    }

    /** The string a resource holds, or null when [id] isn't one (or has none). */
    public String stringFor(int id) {
        ResourceEntry entry = entryById.get(id);
        if (entry == null || table == null) return null;
        try {
            return entry.toStringValue(table, Locale.ENGLISH);
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public String getString(int id) {
        String s = stringFor(id);
        if (s == null) throw new NotFoundException("String resource ID #0x" + Integer.toHexString(id));
        return s;
    }

    @Override
    public String getString(int id, Object... formatArgs) {
        return String.format(getString(id), formatArgs);
    }

    @Override
    public CharSequence getText(int id) {
        return getString(id);
    }

    @Override
    public CharSequence getText(int id, CharSequence def) {
        String s = stringFor(id);
        return s == null ? def : s;
    }

    @Override
    public DisplayMetrics getDisplayMetrics() {
        return METRICS;
    }

    @Override
    public Configuration getConfiguration() {
        return new Configuration();
    }

    @Override
    public Drawable getDrawable(int id) {
        return new ColorDrawable();
    }

    @Override
    public Drawable getDrawable(int id, Theme theme) {
        return new ColorDrawable();
    }

    @Override
    public int getColor(int id) {
        return 0;
    }

    @Override
    public int getColor(int id, Theme theme) {
        return 0;
    }

    @Override
    public XmlResourceParser getLayout(int id) {
        String path = stringFor(id);
        if (path == null) throw new NotFoundException("Layout resource ID #0x" + Integer.toHexString(id));
        LayoutNode root;
        try (InputStream in = open(path)) {
            if (in == null) throw new NotFoundException(path);
            root = parseLayout(in.readAllBytes());
        } catch (IOException e) {
            throw new NotFoundException(path);
        }
        return (XmlResourceParser) Proxy.newProxyInstance(
                PluginResources.class.getClassLoader(),
                new Class<?>[]{XmlResourceParser.class, LayoutHolder.class},
                (proxy, method, args) -> {
                    if (method.getDeclaringClass() == LayoutHolder.class) return root;
                    Class<?> rt = method.getReturnType();
                    if (rt == boolean.class) return false;
                    if (rt == int.class) return 0;
                    if (rt == float.class) return 0f;
                    return null;
                });
    }

    private LayoutNode parseLayout(byte[] bytes) {
        BinaryXmlParser parser = new BinaryXmlParser(ByteBuffer.wrap(bytes), table);
        parser.setLocale(Locale.ENGLISH);
        Deque<LayoutNode> stack = new ArrayDeque<>();
        LayoutNode[] root = new LayoutNode[1];
        parser.setXmlStreamer(new XmlStreamer() {
            @Override
            public void onStartTag(XmlNodeStartTag tag) {
                LayoutNode node = new LayoutNode(tag.getName());
                for (Attribute attr : tag.getAttributes().values()) {
                    if (attr == null) continue;
                    ResourceValue typed = attr.getTypedValue();
                    if (typed instanceof ResourceValue.ReferenceResourceValue) {
                        int ref = (int) ((ResourceValue.ReferenceResourceValue) typed).getReferenceResourceId();
                        node.refs.put(attr.getName(), ref);
                        String text = stringFor(ref);
                        if (text != null) node.attrs.put(attr.getName(), text);
                    } else {
                        node.attrs.put(attr.getName(), attr.toStringValue(table, Locale.ENGLISH));
                    }
                }
                if (stack.isEmpty()) root[0] = node;
                else stack.peek().children.add(node);
                stack.push(node);
            }

            @Override
            public void onEndTag(XmlNodeEndTag tag) {
                stack.pop();
            }

            @Override
            public void onCData(XmlCData cdata) {}

            @Override
            public void onNamespaceStart(XmlNamespaceStartTag tag) {}

            @Override
            public void onNamespaceEnd(XmlNamespaceEndTag tag) {}
        });
        parser.parse();
        return root[0];
    }
}
