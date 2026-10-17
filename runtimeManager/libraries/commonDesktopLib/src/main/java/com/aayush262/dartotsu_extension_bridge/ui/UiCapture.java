package com.aayush262.dartotsu_extension_bridge.ui;

import android.view.LayoutInflater;
import android.view.View;

import androidx.fragment.app.DialogFragment;
import androidx.fragment.app.Fragment;

import com.aayush262.dartotsu_extension_bridge.logger.LogLevel;
import com.aayush262.dartotsu_extension_bridge.logger.Logger;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;

/**
 * Runs an extension's settings code against the desktop view stand-ins and
 * hands back the screens it opened. While a capture is running,
 * {@link DialogFragment#show} registers the fragment here instead of
 * doing nothing, and {@link #build} drives its creation callbacks so the
 * fragment ends up with a real view tree to read.
 */
public final class UiCapture {
    private static final ThreadLocal<UiCapture> CURRENT = new ThreadLocal<>();
    private static PluginResources fallback;

    private final PluginResources resources;
    private final List<DialogFragment> shown = new ArrayList<>();

    private UiCapture(PluginResources resources) {
        this.resources = resources;
    }

    /** Resources of the extension being captured, for ids its views reference. */
    public static PluginResources resources() {
        UiCapture capture = CURRENT.get();
        if (capture != null) return capture.resources;
        try {
            if (fallback == null) fallback = new PluginResources(UiCapture.class.getClassLoader());
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        return fallback;
    }

    public static boolean isCapturing() {
        return CURRENT.get() != null;
    }

    /** Called by [DialogFragment.show]. */
    public static void shown(DialogFragment fragment) {
        UiCapture capture = CURRENT.get();
        if (capture != null) capture.shown.add(fragment);
    }

    /**
     * Runs [action] and returns the fragments it showed, each built to the
     * point where {@link Fragment#getView()} is the inflated screen.
     */
    public static List<DialogFragment> capture(PluginResources resources, Callable<?> action) throws Exception {
        UiCapture previous = CURRENT.get();
        UiCapture capture = new UiCapture(resources);
        CURRENT.set(capture);
        try {
            try {
                action.call();
            } catch (Throwable e) {
                // The extension hit something missing here; what it showed before that still counts.
                Logger.log("Settings action stopped early: " + e, LogLevel.DEBUG);
            }
            List<DialogFragment> built = new ArrayList<>();
            for (DialogFragment fragment : capture.shown) {
                build(fragment);
                built.add(fragment);
            }
            capture.shown.clear();
            return built;
        } finally {
            if (previous == null) CURRENT.remove();
            else CURRENT.set(previous);
        }
    }

    private static void build(DialogFragment fragment) {
        LayoutInflater inflater = LayoutInflater.from(fragment.getContext());
        fragment.attachInflater(inflater);
        step(() -> fragment.onCreate(null));
        View[] root = new View[1];
        step(() -> root[0] = fragment.onCreateView(inflater, null, null));
        if (root[0] == null) return;
        fragment.attachView(root[0]);
        step(() -> fragment.onViewCreated(root[0], null));
        step(fragment::onStart);
        step(fragment::onResume);
    }

    private static void step(Runnable r) {
        try {
            r.run();
        } catch (Throwable ignored) { 
            // A callback that needs more of Android than exists here; whatever
            // it built before failing is still on the screen.
        }
    }
}
