package android.os;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Dartotsu version - no config dependency
 */
public class SystemProperties {

    public static final int PROP_VALUE_MAX = 91;

    private static final Map<String, String> props = new ConcurrentHashMap<>();

    private static String native_get(String key) {
        return props.getOrDefault(key, "");
    }

    private static String native_get(String key, String def) {
        return props.getOrDefault(key, def != null ? def : "");
    }

    private static int native_get_int(String key, int def) {
        try {
            return Integer.parseInt(props.get(key));
        } catch (Exception e) {
            return def;
        }
    }

    private static long native_get_long(String key, long def) {
        try {
            return Long.parseLong(props.get(key));
        } catch (Exception e) {
            return def;
        }
    }

    private static boolean native_get_boolean(String key, boolean def) {
        String val = props.get(key);
        if (val == null) return def;

        return switch (val) {
            case "1", "true", "y", "yes", "on" -> true;
            case "0", "false", "n", "no", "off" -> false;
            default -> def;
        };
    }

    private static void native_set(String key, String val) {
        if (val == null) return;
        props.put(key, val);
    }

    // ---- Public API ----

    public static String get(String key) {
        return native_get(key);
    }

    public static String get(String key, String def) {
        return native_get(key, def);
    }

    public static int getInt(String key, int def) {
        return native_get_int(key, def);
    }

    public static long getLong(String key, long def) {
        return native_get_long(key, def);
    }

    public static boolean getBoolean(String key, boolean def) {
        return native_get_boolean(key, def);
    }

    public static void set(String key, String val) {
        if (val != null && val.length() > PROP_VALUE_MAX) {
            throw new IllegalArgumentException("val.length > " + PROP_VALUE_MAX);
        }
        native_set(key, val);
    }
}