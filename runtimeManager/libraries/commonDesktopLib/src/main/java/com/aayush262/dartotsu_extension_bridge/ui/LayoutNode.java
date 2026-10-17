package com.aayush262.dartotsu_extension_bridge.ui;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * One element of a compiled layout (`res/layout/*.xml` inside an extension),
 * kept as a plain tree so the inflater doesn't need a pull parser.
 * Attribute names are local (`text`, not `android:text`); [refs] holds the
 * resource id of the attributes that point at another resource (`@id/save`).
 */
public final class LayoutNode {
    public final String tag;
    public final Map<String, String> attrs = new HashMap<>();
    public final Map<String, Integer> refs = new HashMap<>();
    public final List<LayoutNode> children = new ArrayList<>();

    public LayoutNode(String tag) {
        this.tag = tag;
    }
}
