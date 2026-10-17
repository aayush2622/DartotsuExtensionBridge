/*
 * Copyright (C) 2006 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package android.view;

import android.animation.AnimatorInflater;
import android.animation.StateListAnimator;
import android.annotation.AttrRes;
import android.annotation.CallSuper;
import android.annotation.ColorInt;
import android.annotation.DrawableRes;
import android.annotation.FloatRange;
import android.annotation.IdRes;
import android.annotation.IntRange;
import android.annotation.LayoutRes;
import android.annotation.NonNull;
import android.annotation.Nullable;
import android.annotation.RequiresPermission;
import android.annotation.Size;
import android.annotation.StyleRes;
import android.annotation.SuppressLint;
import android.annotation.SystemApi;
import android.annotation.TestApi;
import android.annotation.UiThread;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.ClipDescription;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.IntentSender;
import android.content.res.ColorStateList;
import android.content.res.CompatibilityInfo;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.content.res.TypedArray;
import android.graphics.Bitmap;
import android.graphics.BlendMode;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Interpolator;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Point;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RecordingCanvas;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Region;
import android.graphics.RenderNode;
import android.graphics.Shader;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.hardware.input.InputManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Message;
import android.os.Parcel;
import android.os.Parcelable;
import android.os.RemoteException;
import android.os.SystemClock;
import android.os.Trace;
import android.text.InputType;
import android.text.TextUtils;
import android.util.ArraySet;
import android.util.AttributeSet;
import android.util.DisplayMetrics;
import android.util.FloatProperty;
import android.util.LayoutDirection;
import android.util.Log;
import android.util.LongSparseArray;
import android.util.Pair;
import android.util.Property;
import android.util.SparseArray;
import android.util.SparseIntArray;
import android.util.StateSet;
import android.util.TimeUtils;
import android.util.TypedValue;
import android.view.ContextMenu.ContextMenuInfo;
import android.view.WindowInsets.Type;
import android.view.WindowInsetsAnimation.Bounds;
import android.view.WindowManager.LayoutParams;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityEventSource;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction;
import android.view.accessibility.AccessibilityNodeProvider;
import android.view.accessibility.AccessibilityWindowInfo;
import android.view.animation.Animation;
import android.view.animation.AnimationUtils;
import android.view.animation.Transformation;
import android.view.autofill.AutofillId;
import android.view.autofill.AutofillManager;
import android.view.autofill.AutofillValue;
import android.view.contentcapture.ContentCaptureContext;
import android.view.contentcapture.ContentCaptureManager;
import android.view.contentcapture.ContentCaptureSession;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;
import android.widget.Checkable;

import java.io.PrintWriter;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.ref.WeakReference;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.function.Predicate;

@UiThread
public class View implements Drawable.Callback, KeyEvent.Callback,
        AccessibilityEventSource {
    /** @hide */
    public static boolean DEBUG_DRAW = false;

    protected static final String VIEW_LOG_TAG = "View";

    public static boolean sDebugViewAttributes = false;

    public static String sDebugViewAttributesApplicationPackage;

    public static final int NO_ID = -1;

    public static final int LAST_APP_AUTOFILL_ID = Integer.MAX_VALUE / 2;

    /** @hide */
    // public HapticScrollFeedbackProvider mScrollFeedbackProvider = null;

    static boolean sTextureViewIgnoresDrawableSetters = false;

    protected static boolean sPreserveMarginParamsInLayoutParamConversion;

    static boolean sCascadedDragDrop;

    static boolean sHasFocusableExcludeAutoFocusable;

    static boolean sBrokenInsetsDispatch;

    protected static boolean sBrokenWindowBackground;

    static boolean sForceLayoutWhenInsetsChanged;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface Focusable {}

    public static final int NOT_FOCUSABLE = 0x00000000;

    public static final int FOCUSABLE = 0x00000001;

    public static final int FOCUSABLE_AUTO = 0x00000010;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface Visibility {}

    public static final int VISIBLE = 0x00000000;

    public static final int INVISIBLE = 0x00000004;

    public static final int GONE = 0x00000008;

    static final int VISIBILITY_MASK = 0x0000000C;

    public static final String AUTOFILL_HINT_EMAIL_ADDRESS = "emailAddress";

    public static final String AUTOFILL_HINT_NAME = "name";

    public static final String AUTOFILL_HINT_USERNAME = "username";

    public static final String AUTOFILL_HINT_PASSWORD = "password";

    public static final String AUTOFILL_HINT_PHONE = "phone";

    public static final String AUTOFILL_HINT_POSTAL_ADDRESS = "postalAddress";

    public static final String AUTOFILL_HINT_POSTAL_CODE = "postalCode";

    public static final String AUTOFILL_HINT_CREDIT_CARD_NUMBER = "creditCardNumber";

    public static final String AUTOFILL_HINT_CREDIT_CARD_SECURITY_CODE = "creditCardSecurityCode";

    public static final String AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_DATE =
            "creditCardExpirationDate";

    public static final String AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_MONTH =
            "creditCardExpirationMonth";

    public static final String AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_YEAR =
            "creditCardExpirationYear";

    public static final String AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_DAY = "creditCardExpirationDay";

    // TODO(229765029): unhide this for UI toolkit
    public static final String AUTOFILL_HINT_PASSWORD_AUTO = "passwordAuto";

    public static final String AUTOFILL_HINT_CREDENTIAL_MANAGER = "credential";

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface AutofillType {}

    public static final int AUTOFILL_TYPE_NONE = 0;

    public static final int AUTOFILL_TYPE_TEXT = 1;

    public static final int AUTOFILL_TYPE_TOGGLE = 2;

    public static final int AUTOFILL_TYPE_LIST = 3;

    public static final int AUTOFILL_TYPE_DATE = 4;


    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface AutofillImportance {}

    public static final int IMPORTANT_FOR_AUTOFILL_AUTO = 0x0;

    public static final int IMPORTANT_FOR_AUTOFILL_YES = 0x1;

    public static final int IMPORTANT_FOR_AUTOFILL_NO = 0x2;

    public static final int IMPORTANT_FOR_AUTOFILL_YES_EXCLUDE_DESCENDANTS = 0x4;

    public static final int IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS = 0x8;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface AutofillFlags {}

    public static final int AUTOFILL_FLAG_INCLUDE_NOT_IMPORTANT_VIEWS = 0x1;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ContentCaptureImportance {}

    public static final int IMPORTANT_FOR_CONTENT_CAPTURE_AUTO = 0x0;

    public static final int IMPORTANT_FOR_CONTENT_CAPTURE_YES = 0x1;

    public static final int IMPORTANT_FOR_CONTENT_CAPTURE_NO = 0x2;

    public static final int IMPORTANT_FOR_CONTENT_CAPTURE_YES_EXCLUDE_DESCENDANTS = 0x4;

    public static final int IMPORTANT_FOR_CONTENT_CAPTURE_NO_EXCLUDE_DESCENDANTS = 0x8;

    /** {@hide} */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ScrollCaptureHint {}

    public static final int SCROLL_CAPTURE_HINT_AUTO = 0;

    public static final int SCROLL_CAPTURE_HINT_EXCLUDE = 0x1;

    public static final int SCROLL_CAPTURE_HINT_INCLUDE = 0x2;

    public static final int SCROLL_CAPTURE_HINT_EXCLUDE_DESCENDANTS = 0x4;

    static final int ENABLED = 0x00000000;

    static final int DISABLED = 0x00000020;

    static final int ENABLED_MASK = 0x00000020;

    static final int WILL_NOT_DRAW = 0x00000080;

    static final int DRAW_MASK = 0x00000080;

    static final int SCROLLBARS_NONE = 0x00000000;

    static final int SCROLLBARS_HORIZONTAL = 0x00000100;

    static final int SCROLLBARS_VERTICAL = 0x00000200;

    static final int SCROLLBARS_MASK = 0x00000300;

    static final int FILTER_TOUCHES_WHEN_OBSCURED = 0x00000400;

    static final int OPTIONAL_FITS_SYSTEM_WINDOWS = 0x00000800;

    static final int FADING_EDGE_NONE = 0x00000000;

    static final int FADING_EDGE_HORIZONTAL = 0x00001000;

    static final int FADING_EDGE_VERTICAL = 0x00002000;

    static final int FADING_EDGE_MASK = 0x00003000;

    static final int CLICKABLE = 0x00004000;

    static final int DRAWING_CACHE_ENABLED = 0x00008000;

    static final int SAVE_DISABLED = 0x000010000;

    static final int SAVE_DISABLED_MASK = 0x000010000;

    static final int WILL_NOT_CACHE_DRAWING = 0x000020000;

    static final int FOCUSABLE_IN_TOUCH_MODE = 0x00040000;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface DrawingCacheQuality {}

    @Deprecated
    public static final int DRAWING_CACHE_QUALITY_LOW = 0x00080000;

    @Deprecated
    public static final int DRAWING_CACHE_QUALITY_HIGH = 0x00100000;

    @Deprecated
    public static final int DRAWING_CACHE_QUALITY_AUTO = 0x00000000;

    static final int DRAWING_CACHE_QUALITY_MASK = 0x00180000;

    static final int LONG_CLICKABLE = 0x00200000;

    static final int DUPLICATE_PARENT_STATE = 0x00400000;

    static final int CONTEXT_CLICKABLE = 0x00800000;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ScrollBarStyle {}

    public static final int SCROLLBARS_INSIDE_OVERLAY = 0;

    public static final int SCROLLBARS_INSIDE_INSET = 0x01000000;

    public static final int SCROLLBARS_OUTSIDE_OVERLAY = 0x02000000;

    public static final int SCROLLBARS_OUTSIDE_INSET = 0x03000000;

    static final int SCROLLBARS_INSET_MASK = 0x01000000;

    static final int SCROLLBARS_OUTSIDE_MASK = 0x02000000;

    static final int SCROLLBARS_STYLE_MASK = 0x03000000;

    public static final int KEEP_SCREEN_ON = 0x04000000;

    public static final int SOUND_EFFECTS_ENABLED = 0x08000000;

    public static final int HAPTIC_FEEDBACK_ENABLED = 0x10000000;

    static final int PARENT_SAVE_DISABLED = 0x20000000;

    static final int PARENT_SAVE_DISABLED_MASK = 0x20000000;

    static final int TOOLTIP = 0x40000000;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ContentSensitivity {}

    public static final int CONTENT_SENSITIVITY_AUTO = 0x0;

    public static final int CONTENT_SENSITIVITY_SENSITIVE = 0x1;

    public static final int CONTENT_SENSITIVITY_NOT_SENSITIVE = 0x2;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface FocusableMode {}

    public static final int FOCUSABLES_ALL = 0x00000000;

    public static final int FOCUSABLES_TOUCH_MODE = 0x00000001;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface FocusDirection {}

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface FocusRealDirection {} // Like @FocusDirection, but without forward/backward

    public static final int FOCUS_BACKWARD = 0x00000001;

    public static final int FOCUS_FORWARD = 0x00000002;

    public static final int FOCUS_LEFT = 0x00000011;

    public static final int FOCUS_UP = 0x00000021;

    public static final int FOCUS_RIGHT = 0x00000042;

    public static final int FOCUS_DOWN = 0x00000082;

    public static final int MEASURED_SIZE_MASK = 0x00ffffff;

    public static final int MEASURED_STATE_MASK = 0xff000000;

    public static final int MEASURED_HEIGHT_STATE_SHIFT = 16;

    public static final int MEASURED_STATE_TOO_SMALL = 0x01000000;

    // Singles
    protected static final int[] EMPTY_STATE_SET = new int[0];
    protected static final int[] ENABLED_STATE_SET = new int[0];
    protected static final int[] FOCUSED_STATE_SET = new int[0];
    protected static final int[] SELECTED_STATE_SET = new int[0];
    protected static final int[] PRESSED_STATE_SET = new int[0];
    protected static final int[] WINDOW_FOCUSED_STATE_SET = new int[0];
    // Doubles
    protected static final int[] ENABLED_FOCUSED_STATE_SET = new int[0];
    protected static final int[] ENABLED_SELECTED_STATE_SET = new int[0];
    protected static final int[] ENABLED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] FOCUSED_SELECTED_STATE_SET = new int[0];
    protected static final int[] FOCUSED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    // Triples
    protected static final int[] ENABLED_FOCUSED_SELECTED_STATE_SET = new int[0];
    protected static final int[] ENABLED_FOCUSED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] ENABLED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] FOCUSED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] ENABLED_FOCUSED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_SELECTED_STATE_SET = new int[0];
    protected static final int[] PRESSED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_FOCUSED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_FOCUSED_SELECTED_STATE_SET = new int[0];
    protected static final int[] PRESSED_FOCUSED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_SELECTED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_FOCUSED_WINDOW_FOCUSED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_FOCUSED_SELECTED_STATE_SET = new int[0];
    protected static final int[] PRESSED_ENABLED_FOCUSED_SELECTED_WINDOW_FOCUSED_STATE_SET = new int[0];

    public static final int FRAME_RATE_CATEGORY_REASON_UNKNOWN = 0x0000_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_SMALL = 0x0100_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_INTERMITTENT = 0x0200_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_LARGE = 0x03000000;

    public static final int FRAME_RATE_CATEGORY_REASON_REQUESTED = 0x0400_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_INVALID = 0x0500_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_VELOCITY = 0x0600_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_BOOST = 0x0800_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_TOUCH = 0x0900_0000;

    public static final int FRAME_RATE_CATEGORY_REASON_CONFLICTED = 0x0A00_0000;

    protected static boolean sToolkitSetFrameRateReadOnlyFlagValue;

    // Used to set frame rate compatibility.
    int mFrameRateCompatibility;

    static final int DEBUG_CORNERS_COLOR = 0;

    static final int DEBUG_CORNERS_SIZE_DIP = 8;

    static final ThreadLocal<Rect> sThreadLocal = ThreadLocal.withInitial(Rect::new);

    protected Animation mCurrentAnimation = null;

    @ViewDebug.ExportedProperty(category = "measurement")
    int mMeasuredWidth;

    @ViewDebug.ExportedProperty(category = "measurement")
    int mMeasuredHeight;

    boolean mRecreateDisplayList = false;

    @IdRes
    @ViewDebug.ExportedProperty(resolveId = true)
    int mID = NO_ID;
    protected Object mTag = null;

    /*
     * Masks for mPrivateFlags, as generated by dumpFlags():
     *
     * |-------|-------|-------|-------|
     *                                 1 PFLAG_WANTS_FOCUS
     *                                1  PFLAG_FOCUSED
     *                               1   PFLAG_SELECTED
     *                              1    PFLAG_IS_ROOT_NAMESPACE
     *                             1     PFLAG_HAS_BOUNDS
     *                            1      PFLAG_DRAWN
     *                           1       PFLAG_DRAW_ANIMATION
     *                          1        PFLAG_SKIP_DRAW
     *                        1          PFLAG_REQUEST_TRANSPARENT_REGIONS
     *                       1           PFLAG_DRAWABLE_STATE_DIRTY
     *                      1            PFLAG_MEASURED_DIMENSION_SET
     *                     1             PFLAG_FORCE_LAYOUT
     *                    1              PFLAG_LAYOUT_REQUIRED
     *                   1               PFLAG_PRESSED
     *                  1                PFLAG_DRAWING_CACHE_VALID
     *                 1                 PFLAG_ANIMATION_STARTED
     *                1                  PFLAG_SAVE_STATE_CALLED
     *               1                   PFLAG_ALPHA_SET
     *              1                    PFLAG_SCROLL_CONTAINER
     *             1                     PFLAG_SCROLL_CONTAINER_ADDED
     *            1                      PFLAG_DIRTY
     *            1                      PFLAG_DIRTY_MASK
     *          1                        PFLAG_OPAQUE_BACKGROUND
     *         1                         PFLAG_OPAQUE_SCROLLBARS
     *         11                        PFLAG_OPAQUE_MASK
     *        1                          PFLAG_PREPRESSED
     *       1                           PFLAG_CANCEL_NEXT_UP_EVENT
     *      1                            PFLAG_AWAKEN_SCROLL_BARS_ON_ATTACH
     *     1                             PFLAG_HOVERED
     *    1                              PFLAG_NOTIFY_AUTOFILL_MANAGER_ON_CLICK
     *   1                               PFLAG_ACTIVATED
     *  1                                PFLAG_INVALIDATED
     * |-------|-------|-------|-------|
     */
    /** {@hide} */
    static final int PFLAG_WANTS_FOCUS                 = 0x00000001;
    /** {@hide} */
    static final int PFLAG_FOCUSED                     = 0x00000002;
    /** {@hide} */
    static final int PFLAG_SELECTED                    = 0x00000004;
    /** {@hide} */
    static final int PFLAG_IS_ROOT_NAMESPACE           = 0x00000008;
    /** {@hide} */
    static final int PFLAG_HAS_BOUNDS                  = 0x00000010;
    /** {@hide} */
    static final int PFLAG_DRAWN                       = 0x00000020;
    static final int PFLAG_DRAW_ANIMATION              = 0x00000040;
    /** {@hide} */
    static final int PFLAG_SKIP_DRAW                   = 0x00000080;
    /** {@hide} */
    static final int PFLAG_REQUEST_TRANSPARENT_REGIONS = 0x00000200;
    /** {@hide} */
    static final int PFLAG_DRAWABLE_STATE_DIRTY        = 0x00000400;
    /** {@hide} */
    static final int PFLAG_MEASURED_DIMENSION_SET      = 0x00000800;
    /** {@hide} */
    static final int PFLAG_FORCE_LAYOUT                = 0x00001000;
    /** {@hide} */
    static final int PFLAG_LAYOUT_REQUIRED             = 0x00002000;

    /** {@hide} */
    static final int PFLAG_DRAWING_CACHE_VALID         = 0x00008000;
    static final int PFLAG_ANIMATION_STARTED           = 0x00010000;

    static final int PFLAG_ALPHA_SET                   = 0x00040000;

    static final int PFLAG_SCROLL_CONTAINER            = 0x00080000;

    static final int PFLAG_SCROLL_CONTAINER_ADDED      = 0x00100000;

    static final int PFLAG_DIRTY                       = 0x00200000;

    static final int PFLAG_DIRTY_MASK                  = 0x00200000;

    static final int PFLAG_OPAQUE_BACKGROUND           = 0x00800000;

    static final int PFLAG_OPAQUE_SCROLLBARS           = 0x01000000;

    static final int PFLAG_OPAQUE_MASK                 = 0x01800000;

    static final int PFLAG_CANCEL_NEXT_UP_EVENT        = 0x04000000;

    /** {@hide} */
    static final int PFLAG_ACTIVATED                   = 0x40000000;

    static final int PFLAG_INVALIDATED                 = 0x80000000;

    /* End of masks for mPrivateFlags */

    /*
     * Masks for mPrivateFlags2, as generated by dumpFlags():
     *
     * |-------|-------|-------|-------|
     *                                 1 PFLAG2_DRAG_CAN_ACCEPT
     *                                1  PFLAG2_DRAG_HOVERED
     *                              11   PFLAG2_LAYOUT_DIRECTION_MASK
     *                             1     PFLAG2_LAYOUT_DIRECTION_RESOLVED_RTL
     *                            1      PFLAG2_LAYOUT_DIRECTION_RESOLVED
     *                            11     PFLAG2_LAYOUT_DIRECTION_RESOLVED_MASK
     *                           1       PFLAG2_TEXT_DIRECTION_FLAGS[1]
     *                          1        PFLAG2_TEXT_DIRECTION_FLAGS[2]
     *                          11       PFLAG2_TEXT_DIRECTION_FLAGS[3]
     *                         1         PFLAG2_TEXT_DIRECTION_FLAGS[4]
     *                         1 1       PFLAG2_TEXT_DIRECTION_FLAGS[5]
     *                         11        PFLAG2_TEXT_DIRECTION_FLAGS[6]
     *                         111       PFLAG2_TEXT_DIRECTION_FLAGS[7]
     *                         111       PFLAG2_TEXT_DIRECTION_MASK
     *                        1          PFLAG2_TEXT_DIRECTION_RESOLVED
     *                       1           PFLAG2_TEXT_DIRECTION_RESOLVED_DEFAULT
     *                     111           PFLAG2_TEXT_DIRECTION_RESOLVED_MASK
     *                    1              PFLAG2_TEXT_ALIGNMENT_FLAGS[1]
     *                   1               PFLAG2_TEXT_ALIGNMENT_FLAGS[2]
     *                   11              PFLAG2_TEXT_ALIGNMENT_FLAGS[3]
     *                  1                PFLAG2_TEXT_ALIGNMENT_FLAGS[4]
     *                  1 1              PFLAG2_TEXT_ALIGNMENT_FLAGS[5]
     *                  11               PFLAG2_TEXT_ALIGNMENT_FLAGS[6]
     *                  111              PFLAG2_TEXT_ALIGNMENT_MASK
     *                 1                 PFLAG2_TEXT_ALIGNMENT_RESOLVED
     *                1                  PFLAG2_TEXT_ALIGNMENT_RESOLVED_DEFAULT
     *              111                  PFLAG2_TEXT_ALIGNMENT_RESOLVED_MASK
     *           111                     PFLAG2_IMPORTANT_FOR_ACCESSIBILITY_MASK
     *         11                        PFLAG2_ACCESSIBILITY_LIVE_REGION_MASK
     *       1                           PFLAG2_ACCESSIBILITY_FOCUSED
     *      1                            PFLAG2_SUBTREE_ACCESSIBILITY_STATE_CHANGED
     *     1                             PFLAG2_VIEW_QUICK_REJECTED
     *    1                              PFLAG2_PADDING_RESOLVED
     *   1                               PFLAG2_DRAWABLE_RESOLVED
     *  1                                PFLAG2_HAS_TRANSIENT_STATE
     * |-------|-------|-------|-------|
     */

    static final int PFLAG2_DRAG_CAN_ACCEPT            = 0x00000001;

    static final int PFLAG2_DRAG_HOVERED               = 0x00000002;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    // Not called LayoutDirection to avoid conflict with android.util.LayoutDirection
    public @interface LayoutDir {}

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ResolvedLayoutDir {}

    public static final int LAYOUT_DIRECTION_UNDEFINED = 0;

    public static final int LAYOUT_DIRECTION_LTR = LayoutDirection.LTR;

    public static final int LAYOUT_DIRECTION_RTL = LayoutDirection.RTL;

    public static final int LAYOUT_DIRECTION_INHERIT = LayoutDirection.INHERIT;

    public static final int LAYOUT_DIRECTION_LOCALE = LayoutDirection.LOCALE;

    static final int PFLAG2_LAYOUT_DIRECTION_MASK_SHIFT = 2;

    static final int PFLAG2_LAYOUT_DIRECTION_MASK = 0x00000003 << PFLAG2_LAYOUT_DIRECTION_MASK_SHIFT;

    static final int PFLAG2_LAYOUT_DIRECTION_RESOLVED_RTL = 4 << PFLAG2_LAYOUT_DIRECTION_MASK_SHIFT;

    static final int PFLAG2_LAYOUT_DIRECTION_RESOLVED = 8 << PFLAG2_LAYOUT_DIRECTION_MASK_SHIFT;

    static final int PFLAG2_LAYOUT_DIRECTION_RESOLVED_MASK = 0x0000000C
            << PFLAG2_LAYOUT_DIRECTION_MASK_SHIFT;

    static final int LAYOUT_DIRECTION_RESOLVED_DEFAULT = LAYOUT_DIRECTION_LTR;

    public static final int TEXT_DIRECTION_INHERIT = 0;

    public static final int TEXT_DIRECTION_FIRST_STRONG = 1;

    public static final int TEXT_DIRECTION_ANY_RTL = 2;

    public static final int TEXT_DIRECTION_LTR = 3;

    public static final int TEXT_DIRECTION_RTL = 4;

    public static final int TEXT_DIRECTION_LOCALE = 5;

    public static final int TEXT_DIRECTION_FIRST_STRONG_LTR = 6;

    public static final int TEXT_DIRECTION_FIRST_STRONG_RTL = 7;

    static final int TEXT_DIRECTION_RESOLVED_DEFAULT = TEXT_DIRECTION_FIRST_STRONG;

    static final int PFLAG2_TEXT_DIRECTION_MASK_SHIFT = 6;

    static final int PFLAG2_TEXT_DIRECTION_MASK = 0x00000007
            << PFLAG2_TEXT_DIRECTION_MASK_SHIFT;

    static final int PFLAG2_TEXT_DIRECTION_RESOLVED = 0x00000008
            << PFLAG2_TEXT_DIRECTION_MASK_SHIFT;

    static final int PFLAG2_TEXT_DIRECTION_RESOLVED_MASK_SHIFT = 10;

    static final int PFLAG2_TEXT_DIRECTION_RESOLVED_MASK = 0x00000007
            << PFLAG2_TEXT_DIRECTION_RESOLVED_MASK_SHIFT;

    static final int PFLAG2_TEXT_DIRECTION_RESOLVED_DEFAULT =
            TEXT_DIRECTION_RESOLVED_DEFAULT << PFLAG2_TEXT_DIRECTION_RESOLVED_MASK_SHIFT;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface TextAlignment {}

    public static final int TEXT_ALIGNMENT_INHERIT = 0;

    public static final int TEXT_ALIGNMENT_GRAVITY = 1;

    public static final int TEXT_ALIGNMENT_TEXT_START = 2;

    public static final int TEXT_ALIGNMENT_TEXT_END = 3;

    public static final int TEXT_ALIGNMENT_CENTER = 4;

    public static final int TEXT_ALIGNMENT_VIEW_START = 5;

    public static final int TEXT_ALIGNMENT_VIEW_END = 6;

    static final int TEXT_ALIGNMENT_RESOLVED_DEFAULT = TEXT_ALIGNMENT_GRAVITY;

    static final int PFLAG2_TEXT_ALIGNMENT_MASK_SHIFT = 13;

    static final int PFLAG2_TEXT_ALIGNMENT_MASK = 0x00000007 << PFLAG2_TEXT_ALIGNMENT_MASK_SHIFT;

    static final int PFLAG2_TEXT_ALIGNMENT_RESOLVED = 0x00000008 << PFLAG2_TEXT_ALIGNMENT_MASK_SHIFT;

    static final int PFLAG2_TEXT_ALIGNMENT_RESOLVED_MASK_SHIFT = 17;

    static final int PFLAG2_TEXT_ALIGNMENT_RESOLVED_MASK = 0x00000007
            << PFLAG2_TEXT_ALIGNMENT_RESOLVED_MASK_SHIFT;

    // Accessiblity constants for mPrivateFlags2

    static final int PFLAG2_IMPORTANT_FOR_ACCESSIBILITY_SHIFT = 20;

    public static final int IMPORTANT_FOR_ACCESSIBILITY_AUTO = 0x00000000;

    public static final int IMPORTANT_FOR_ACCESSIBILITY_YES = 0x00000001;

    public static final int IMPORTANT_FOR_ACCESSIBILITY_NO = 0x00000002;

    public static final int IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS = 0x00000004;

    static final int IMPORTANT_FOR_ACCESSIBILITY_DEFAULT = IMPORTANT_FOR_ACCESSIBILITY_AUTO;

    public static final int ACCESSIBILITY_DATA_SENSITIVE_AUTO = 0x00000000;

    public static final int ACCESSIBILITY_DATA_SENSITIVE_YES = 0x00000001;

    public static final int ACCESSIBILITY_DATA_SENSITIVE_NO = 0x00000002;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface AccessibilityDataSensitive {}

    static final int PFLAG2_IMPORTANT_FOR_ACCESSIBILITY_MASK = (IMPORTANT_FOR_ACCESSIBILITY_AUTO
        | IMPORTANT_FOR_ACCESSIBILITY_YES | IMPORTANT_FOR_ACCESSIBILITY_NO
        | IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS)
        << PFLAG2_IMPORTANT_FOR_ACCESSIBILITY_SHIFT;

    static final int PFLAG2_ACCESSIBILITY_LIVE_REGION_SHIFT = 23;

    public static final int ACCESSIBILITY_LIVE_REGION_NONE = 0x00000000;

    public static final int ACCESSIBILITY_LIVE_REGION_POLITE = 0x00000001;

    public static final int ACCESSIBILITY_LIVE_REGION_ASSERTIVE = 0x00000002;

    static final int ACCESSIBILITY_LIVE_REGION_DEFAULT = ACCESSIBILITY_LIVE_REGION_NONE;

    static final int PFLAG2_ACCESSIBILITY_LIVE_REGION_MASK = (ACCESSIBILITY_LIVE_REGION_NONE
            | ACCESSIBILITY_LIVE_REGION_POLITE | ACCESSIBILITY_LIVE_REGION_ASSERTIVE)
            << PFLAG2_ACCESSIBILITY_LIVE_REGION_SHIFT;

    static final int PFLAG2_ACCESSIBILITY_FOCUSED = 0x04000000;

    static final int PFLAG2_SUBTREE_ACCESSIBILITY_STATE_CHANGED = 0x08000000;

    static final int PFLAG2_VIEW_QUICK_REJECTED = 0x10000000;

    static final int PFLAG2_PADDING_RESOLVED = 0x20000000;

    static final int PFLAG2_DRAWABLE_RESOLVED = 0x40000000;

    static final int PFLAG2_HAS_TRANSIENT_STATE = 0x80000000;

    static final int ALL_RTL_PROPERTIES_RESOLVED = PFLAG2_LAYOUT_DIRECTION_RESOLVED |
            PFLAG2_TEXT_DIRECTION_RESOLVED |
            PFLAG2_TEXT_ALIGNMENT_RESOLVED |
            PFLAG2_PADDING_RESOLVED |
            PFLAG2_DRAWABLE_RESOLVED;

    // There are a couple of flags left in mPrivateFlags2

    /* End of masks for mPrivateFlags2 */

    /*
     * Masks for mPrivateFlags3, as generated by dumpFlags():
     *
     * |-------|-------|-------|-------|
     *                                 1 PFLAG3_VIEW_IS_ANIMATING_TRANSFORM
     *                                1  PFLAG3_VIEW_IS_ANIMATING_ALPHA
     *                               1   PFLAG3_IS_LAID_OUT
     *                              1    PFLAG3_MEASURE_NEEDED_BEFORE_LAYOUT
     *                             1     PFLAG3_CALLED_SUPER
     *                            1      PFLAG3_APPLYING_INSETS
     *                           1       PFLAG3_FITTING_SYSTEM_WINDOWS
     *                          1        PFLAG3_NESTED_SCROLLING_ENABLED
     *                         1         PFLAG3_SCROLL_INDICATOR_TOP
     *                        1          PFLAG3_SCROLL_INDICATOR_BOTTOM
     *                       1           PFLAG3_SCROLL_INDICATOR_LEFT
     *                      1            PFLAG3_SCROLL_INDICATOR_RIGHT
     *                     1             PFLAG3_SCROLL_INDICATOR_START
     *                    1              PFLAG3_SCROLL_INDICATOR_END
     *                   1               PFLAG3_ASSIST_BLOCKED
     *                  1                PFLAG3_CLUSTER
     *                 1                 PFLAG3_IS_AUTOFILLED
     *                1                  PFLAG3_FINGER_DOWN
     *               1                   PFLAG3_FOCUSED_BY_DEFAULT
     *           1111                    PFLAG3_IMPORTANT_FOR_AUTOFILL
     *          1                        PFLAG3_OVERLAPPING_RENDERING_FORCED_VALUE
     *         1                         PFLAG3_HAS_OVERLAPPING_RENDERING_FORCED
     *        1                          PFLAG3_TEMPORARY_DETACH
     *       1                           PFLAG3_NO_REVEAL_ON_FOCUS
     *      1                            PFLAG3_NOTIFY_AUTOFILL_ENTER_ON_LAYOUT
     *     1                             PFLAG3_SCREEN_READER_FOCUSABLE
     *    1                              PFLAG3_AGGREGATED_VISIBLE
     *   1                               PFLAG3_AUTOFILLID_EXPLICITLY_SET
     *  1                                PFLAG3_ACCESSIBILITY_HEADING
     * |-------|-------|-------|-------|
     */

    static final int PFLAG3_VIEW_IS_ANIMATING_TRANSFORM = 0x1;

    static final int PFLAG3_VIEW_IS_ANIMATING_ALPHA = 0x2;

    static final int PFLAG3_IS_LAID_OUT = 0x4;

    static final int PFLAG3_MEASURE_NEEDED_BEFORE_LAYOUT = 0x8;

    static final int PFLAG3_CALLED_SUPER = 0x10;

    static final int PFLAG3_APPLYING_INSETS = 0x20;

    static final int PFLAG3_FITTING_SYSTEM_WINDOWS = 0x40;

    static final int PFLAG3_NESTED_SCROLLING_ENABLED = 0x80;

    static final int PFLAG3_SCROLL_INDICATOR_TOP = 0x0100;

    static final int PFLAG3_SCROLL_INDICATOR_BOTTOM = 0x0200;

    static final int PFLAG3_SCROLL_INDICATOR_LEFT = 0x0400;

    static final int PFLAG3_SCROLL_INDICATOR_RIGHT = 0x0800;

    static final int PFLAG3_SCROLL_INDICATOR_START = 0x1000;

    static final int PFLAG3_SCROLL_INDICATOR_END = 0x2000;

    static final int DRAG_MASK = PFLAG2_DRAG_CAN_ACCEPT | PFLAG2_DRAG_HOVERED;

    static final int SCROLL_INDICATORS_NONE = 0x0000;

    static final int SCROLL_INDICATORS_PFLAG3_MASK = PFLAG3_SCROLL_INDICATOR_TOP
            | PFLAG3_SCROLL_INDICATOR_BOTTOM | PFLAG3_SCROLL_INDICATOR_LEFT
            | PFLAG3_SCROLL_INDICATOR_RIGHT | PFLAG3_SCROLL_INDICATOR_START
            | PFLAG3_SCROLL_INDICATOR_END;

    static final int SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT = 8;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ScrollIndicators {}

    public static final int SCROLL_INDICATOR_TOP =
            PFLAG3_SCROLL_INDICATOR_TOP >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    public static final int SCROLL_INDICATOR_BOTTOM =
            PFLAG3_SCROLL_INDICATOR_BOTTOM >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    public static final int SCROLL_INDICATOR_LEFT =
            PFLAG3_SCROLL_INDICATOR_LEFT >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    public static final int SCROLL_INDICATOR_RIGHT =
            PFLAG3_SCROLL_INDICATOR_RIGHT >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    public static final int SCROLL_INDICATOR_START =
            PFLAG3_SCROLL_INDICATOR_START >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    public static final int SCROLL_INDICATOR_END =
            PFLAG3_SCROLL_INDICATOR_END >> SCROLL_INDICATORS_TO_PFLAGS3_LSHIFT;

    static final int PFLAG3_ASSIST_BLOCKED = 0x4000;

    static final int PFLAG3_IMPORTANT_FOR_AUTOFILL_SHIFT = 19;

    static final int PFLAG3_IMPORTANT_FOR_AUTOFILL_MASK = (IMPORTANT_FOR_AUTOFILL_AUTO
            | IMPORTANT_FOR_AUTOFILL_YES | IMPORTANT_FOR_AUTOFILL_NO
            | IMPORTANT_FOR_AUTOFILL_YES_EXCLUDE_DESCENDANTS
            | IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS)
            << PFLAG3_IMPORTANT_FOR_AUTOFILL_SHIFT;

    static final int PFLAG3_TEMPORARY_DETACH = 0x2000000;

    static final int PFLAG3_NOTIFY_AUTOFILL_ENTER_ON_LAYOUT = 0x8000000;

    /* End of masks for mPrivateFlags3 */

    /*
     * Masks for mPrivateFlags4, as generated by dumpFlags():
     *
     * |-------|-------|-------|-------|
     *                             1111 PFLAG4_IMPORTANT_FOR_CONTENT_CAPTURE_MASK
     *                            1     PFLAG4_NOTIFIED_CONTENT_CAPTURE_APPEARED
     *                           1      PFLAG4_NOTIFIED_CONTENT_CAPTURE_DISAPPEARED
     *                          1       PFLAG4_CONTENT_CAPTURE_IMPORTANCE_IS_CACHED
     *                         1        PFLAG4_CONTENT_CAPTURE_IMPORTANCE_CACHED_VALUE
     *                         11       PFLAG4_CONTENT_CAPTURE_IMPORTANCE_MASK
     *                        1         PFLAG4_FRAMEWORK_OPTIONAL_FITS_SYSTEM_WINDOWS
     *                       1          PFLAG4_AUTOFILL_HIDE_HIGHLIGHT
     *                     11           PFLAG4_SCROLL_CAPTURE_HINT_MASK
     *                    1             PFLAG4_ALLOW_CLICK_WHEN_DISABLED
     *                   1              PFLAG4_DETACHED
     *                  1               PFLAG4_HAS_TRANSLATION_TRANSIENT_STATE
     *                 1                PFLAG4_DRAG_A11Y_STARTED
     *                1                 PFLAG4_AUTO_HANDWRITING_INITIATION_ENABLED
     *               1                  PFLAG4_IMPORTANT_FOR_CREDENTIAL_MANAGER
     *              1                   PFLAG4_TRAVERSAL_TRACING_ENABLED
     *             1                    PFLAG4_RELAYOUT_TRACING_ENABLED
     *            1                     PFLAG4_ROTARY_HAPTICS_DETERMINED
     *           1                      PFLAG4_ROTARY_HAPTICS_ENABLED
     *          1                       PFLAG4_ROTARY_HAPTICS_SCROLL_SINCE_LAST_ROTARY_INPUT
     *         1                        PFLAG4_ROTARY_HAPTICS_WAITING_FOR_SCROLL_EVENT
     *       11                         PFLAG4_CONTENT_SENSITIVITY_MASK
     *      1                           PFLAG4_IS_COUNTED_AS_SENSITIVE
     *     1                            PFLAG4_HAS_DRAWN
     *    1                             PFLAG4_HAS_MOVED
     *   1                              PFLAG4_HAS_VIEW_PROPERTY_INVALIDATION
     *  1                               PFLAG4_FORCED_OVERRIDE_FRAME_RATE
     * 1                                PFLAG4_SELF_REQUESTED_FRAME_RATE
     * |-------|-------|-------|-------|
     */

    static final int PFLAG4_FRAMEWORK_OPTIONAL_FITS_SYSTEM_WINDOWS = 0x000000100;

    static final int PFLAG4_SCROLL_CAPTURE_HINT_SHIFT = 10;

    static final int PFLAG4_SCROLL_CAPTURE_HINT_MASK = (SCROLL_CAPTURE_HINT_INCLUDE
            | SCROLL_CAPTURE_HINT_EXCLUDE | SCROLL_CAPTURE_HINT_EXCLUDE_DESCENDANTS)
            << PFLAG4_SCROLL_CAPTURE_HINT_SHIFT;

    /* End of masks for mPrivateFlags4 */

    /** @hide */
    protected static final int VIEW_STRUCTURE_FOR_ASSIST = 0;
    /** @hide */
    protected  static final int VIEW_STRUCTURE_FOR_AUTOFILL = 1;
    /** @hide */
    protected  static final int VIEW_STRUCTURE_FOR_CONTENT_CAPTURE = 2;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface ViewStructureType {}

    public static final int OVER_SCROLL_ALWAYS = 0;

    public static final int OVER_SCROLL_IF_CONTENT_SCROLLS = 1;

    public static final int OVER_SCROLL_NEVER = 2;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_VISIBLE = 0;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_LOW_PROFILE = 0x00000001;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_HIDE_NAVIGATION = 0x00000002;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_FULLSCREEN = 0x00000004;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_LAYOUT_STABLE = 0x00000100;

    public static final int SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION = 0x00000200;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN = 0x00000400;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_IMMERSIVE = 0x00000800;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_IMMERSIVE_STICKY = 0x00001000;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_LIGHT_STATUS_BAR = 0x00002000;

    @Deprecated
    public static final int SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR = 0x00000010;

    @Deprecated
    public static final int STATUS_BAR_HIDDEN = SYSTEM_UI_FLAG_LOW_PROFILE;

    @Deprecated
    public static final int STATUS_BAR_VISIBLE = SYSTEM_UI_FLAG_VISIBLE;

    public static final int STATUS_BAR_DISABLE_EXPAND = 0x00010000;

    public static final int STATUS_BAR_DISABLE_NOTIFICATION_ICONS = 0x00020000;

    public static final int STATUS_BAR_DISABLE_NOTIFICATION_ALERTS = 0x00040000;

    public static final int STATUS_BAR_DISABLE_NOTIFICATION_TICKER = 0x00080000;

    public static final int STATUS_BAR_DISABLE_SYSTEM_INFO = 0x00100000;

    public static final int STATUS_BAR_DISABLE_HOME = 0x00200000;

    public static final int STATUS_BAR_DISABLE_BACK = 0x00400000;

    public static final int STATUS_BAR_DISABLE_CLOCK = 0x00800000;

    public static final int STATUS_BAR_DISABLE_RECENT = 0x01000000;

    public static final int STATUS_BAR_DISABLE_SEARCH = 0x02000000;

    public static final int STATUS_BAR_DISABLE_ONGOING_CALL_CHIP = 0x04000000;

    public static final int PUBLIC_STATUS_BAR_VISIBILITY_MASK = 0x00003FF7;

    public static final int SYSTEM_UI_CLEARABLE_FLAGS =
            SYSTEM_UI_FLAG_LOW_PROFILE | SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | SYSTEM_UI_FLAG_FULLSCREEN;

    @Deprecated
    public static final int SYSTEM_UI_LAYOUT_FLAGS =
            SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface FindViewFlags {}

    public static final int FIND_VIEWS_WITH_TEXT = 0x00000001;

    public static final int FIND_VIEWS_WITH_CONTENT_DESCRIPTION = 0x00000002;

    public static final int FIND_VIEWS_WITH_ACCESSIBILITY_NODE_PROVIDERS = 0x00000004;

    public static final int ACCESSIBILITY_CURSOR_POSITION_UNDEFINED = -1;

    public static final int SCREEN_STATE_OFF = 0x0;

    public static final int SCREEN_STATE_ON = 0x1;

    public static final int SCROLL_AXIS_NONE = 0;

    public static final int SCROLL_AXIS_HORIZONTAL = 1 << 0;

    public static final int SCROLL_AXIS_VERTICAL = 1 << 1;

    protected ViewParent mParent;

    // AttachInfo mAttachInfo;

    /* @hide */
    public int mPrivateFlags;
    int mPrivateFlags2;
    int mPrivateFlags3;

    @SystemUiVisibility
    int mSystemUiVisibility;

    @Retention(RetentionPolicy.SOURCE)
    public @interface SystemUiVisibility {}

    int mTransientStateCount = 0;

    int mWindowAttachCount;

    protected ViewGroup.LayoutParams mLayoutParams;

    @ViewDebug.ExportedProperty(formatToHexString = true)
    int mViewFlags;

    static class TransformationInfo {
        float mTransitionAlpha = 1f;
    }

    /** @hide */
    public TransformationInfo mTransformationInfo;

    @ViewDebug.ExportedProperty(category = "drawing")
    Rect mClipBounds = null;

    @ViewDebug.ExportedProperty(category = "layout")
    protected int mLeft;
    @ViewDebug.ExportedProperty(category = "layout")
    protected int mRight;
    @ViewDebug.ExportedProperty(category = "layout")
    protected int mTop;
    @ViewDebug.ExportedProperty(category = "layout")
    protected int mBottom;

    @ViewDebug.ExportedProperty(category = "scrolling")
    protected int mScrollX;
    @ViewDebug.ExportedProperty(category = "scrolling")
    protected int mScrollY;

    @ViewDebug.ExportedProperty(category = "padding")
    protected int mPaddingLeft = 0;
    @ViewDebug.ExportedProperty(category = "padding")
    protected int mPaddingRight = 0;
    @ViewDebug.ExportedProperty(category = "padding")
    protected int mPaddingTop;
    @ViewDebug.ExportedProperty(category = "padding")
    protected int mPaddingBottom;

    @ViewDebug.ExportedProperty(category = "padding")
    protected int mUserPaddingRight;

    @ViewDebug.ExportedProperty(category = "padding")
    protected int mUserPaddingBottom;

    @ViewDebug.ExportedProperty(category = "padding")
    protected int mUserPaddingLeft;

    @ViewDebug.ExportedProperty(category = "padding")
    int mUserPaddingStart;

    @ViewDebug.ExportedProperty(category = "padding")
    int mUserPaddingEnd;

    int mUserPaddingLeftInitial;

    int mUserPaddingRightInitial;

    int mOldWidthMeasureSpec = Integer.MIN_VALUE;
    int mOldHeightMeasureSpec = Integer.MIN_VALUE;

    RenderNode mBackgroundRenderNode;

    static class TintInfo {
        ColorStateList mTintList;
        BlendMode mBlendMode;
        boolean mHasTintMode;
        boolean mHasTintList;
    }

    // ListenerInfo mListenerInfo;

    // TooltipInfo mTooltipInfo;

    @ViewDebug.ExportedProperty(deepExport = true)
    protected Context mContext;

    ViewOutlineProvider mOutlineProvider = ViewOutlineProvider.BACKGROUND;

    int mNextFocusForwardId = View.NO_ID;

    int mNextClusterForwardId = View.NO_ID;

    boolean mDefaultFocusHighlightEnabled = true;

    public static final int DRAG_FLAG_GLOBAL = 1 << 8;  // 256

    public static final int DRAG_FLAG_GLOBAL_URI_READ = Intent.FLAG_GRANT_READ_URI_PERMISSION;

    public static final int DRAG_FLAG_GLOBAL_URI_WRITE = Intent.FLAG_GRANT_WRITE_URI_PERMISSION;

    public static final int DRAG_FLAG_GLOBAL_PERSISTABLE_URI_PERMISSION =
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION;

    public static final int DRAG_FLAG_GLOBAL_PREFIX_URI_PERMISSION =
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION;

    public static final int DRAG_FLAG_OPAQUE = 1 << 9;

    public static final int DRAG_FLAG_ACCESSIBILITY_ACTION = 1 << 10;

    public static final int DRAG_FLAG_REQUEST_SURFACE_FOR_RETURN_ANIMATION = 1 << 11;

    public static final int DRAG_FLAG_GLOBAL_SAME_APPLICATION = 1 << 12;

    public static final int DRAG_FLAG_START_INTENT_SENDER_ON_UNHANDLED_DRAG = 1 << 13;

    public static final int DRAG_FLAG_HIDE_CALLING_TASK_ON_DRAG_START = 1 << 14;

    public static final int SCROLLBAR_POSITION_DEFAULT = 0;

    public static final int SCROLLBAR_POSITION_LEFT = 1;

    public static final int SCROLLBAR_POSITION_RIGHT = 2;

    public static final int LAYER_TYPE_NONE = 0;

    public static final int LAYER_TYPE_SOFTWARE = 1;

    public static final int LAYER_TYPE_HARDWARE = 2;

    /** @hide */
    @Retention(RetentionPolicy.SOURCE)
    public @interface LayerType {}

    int mLayerType = LAYER_TYPE_NONE;
    Paint mLayerPaint;

    public boolean mCachingFailed;

    final RenderNode mRenderNode;

    AccessibilityDelegate mAccessibilityDelegate;

    ViewOverlay mOverlay;

    // protected final InputEventConsistencyVerifier mInputEventConsistencyVerifier =
    //         InputEventConsistencyVerifier.isInstrumentationEnabled() ?
    //                 new InputEventConsistencyVerifier(this, 0) : null;

    // GhostView mGhostView;

    @ViewDebug.ExportedProperty(category = "attributes", hasAdjacentMapping = true)
    public String[] mAttributes;

    String mStartActivityRequestWho;

    int mUnbufferedInputSource = InputDevice.SOURCE_CLASS_NONE;

    static final float MAX_FRAME_RATE = 120;

    public static final float REQUESTED_FRAME_RATE_CATEGORY_DEFAULT = Float.NaN;
    public static final float REQUESTED_FRAME_RATE_CATEGORY_NO_PREFERENCE = -1;
    public static final float REQUESTED_FRAME_RATE_CATEGORY_LOW = -2;
    public static final float REQUESTED_FRAME_RATE_CATEGORY_NORMAL = -3;
    public static final float REQUESTED_FRAME_RATE_CATEGORY_HIGH = -4;

    public View(Context context) {
        mContext = context;
        mRenderNode = null;
    }

    public View(Context context, @Nullable AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public View(Context context, @Nullable AttributeSet attrs, int defStyleAttr) {
        this(context, attrs, defStyleAttr, 0);
    }

    public View(Context context, @Nullable AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        this(context);
    }

    @NonNull
    public int[] getAttributeResolutionStack(@AttrRes int attribute) {
        return null;
    }

    @NonNull
    @SuppressWarnings("AndroidFrameworkEfficientCollections")
    public Map<Integer, Integer> getAttributeSourceResourceMap() {
        return null;
    }

    @StyleRes
    public int getExplicitStyle() {
        return 0;
    }

    View() {
        mRenderNode = null;
    }

    public final boolean isShowingLayoutBounds() {
        return false;
    }

    @TestApi
    public final void setShowingLayoutBounds(boolean debugLayout) {
        
    }

    public final void saveAttributeDataForStyleable(@NonNull Context context,
            @NonNull int[] styleable, @Nullable AttributeSet attrs, @NonNull TypedArray t,
            int defStyleAttr, int defStyleRes) {
        
    }

    protected void initializeFadingEdge(TypedArray a) {
        
    }

    protected void initializeFadingEdgeInternal(TypedArray a) {
        
    }

    public int getVerticalFadingEdgeLength() {
        return 0;
    }

    public void setFadingEdgeLength(int length) {
        
    }

    public void clearPendingCredentialRequest() {
        
    }

    // public void setPendingCredentialRequest(@NonNull GetCredentialRequest request,
    //         @NonNull OutcomeReceiver<GetCredentialResponse, GetCredentialException> callback) {
    //     
    // }

    // @Nullable
    // public ViewCredentialHandler getViewCredentialHandler() {
    //     
    // }

    public int getHorizontalFadingEdgeLength() {
        return 0;
    }

    public int getVerticalScrollbarWidth() {
        return 0;
    }

    protected int getHorizontalScrollbarHeight() {
        return 0;
    }

    protected void initializeScrollbars(TypedArray a) {
        
    }

    protected void initializeScrollbarsInternal(TypedArray a) {
        
    }

    public void setVerticalScrollbarThumbDrawable(@Nullable Drawable drawable) {
        
    }

    public void setVerticalScrollbarTrackDrawable(@Nullable Drawable drawable) {
        
    }

    public void setHorizontalScrollbarThumbDrawable(@Nullable Drawable drawable) {
        
    }

    public void setHorizontalScrollbarTrackDrawable(@Nullable Drawable drawable) {
        
    }

    public @Nullable Drawable getVerticalScrollbarThumbDrawable() {
        return null;
    }

    public @Nullable Drawable getVerticalScrollbarTrackDrawable() {
        return null;
    }

    public @Nullable Drawable getHorizontalScrollbarThumbDrawable() {
        return null;
    }

    public @Nullable Drawable getHorizontalScrollbarTrackDrawable() {
        return null;
    }

    public void setVerticalScrollbarPosition(int position) {
        
    }

    public int getVerticalScrollbarPosition() {
        return 0;
    }

    boolean isOnScrollbar(float x, float y) {
        return false;
    }

    boolean isOnScrollbarThumb(float x, float y) {
        return false;
    }

    boolean isDraggingScrollBar() {
        return false;
    }

    public void setScrollIndicators(@ScrollIndicators int indicators) {
        
    }

    public void setScrollIndicators(@ScrollIndicators int indicators, @ScrollIndicators int mask) {
        
    }

    @ScrollIndicators
    public int getScrollIndicators() {
        return 0;
    }

    // ListenerInfo getListenerInfo() {
    //     
    // }

    public void setOnScrollChangeListener(OnScrollChangeListener l) {
        
    }

    public void setOnFocusChangeListener(OnFocusChangeListener l) {
        
    }

    public void addOnLayoutChangeListener(OnLayoutChangeListener listener) {
        
    }

    public void removeOnLayoutChangeListener(OnLayoutChangeListener listener) {
        
    }

    public void addOnAttachStateChangeListener(OnAttachStateChangeListener listener) {
        
    }

    public void removeOnAttachStateChangeListener(OnAttachStateChangeListener listener) {
        
    }

    public OnFocusChangeListener getOnFocusChangeListener() {
        return null;
    }

    public void setOnClickListener(@Nullable OnClickListener l) {
        
    }

    public boolean hasOnClickListeners() {
        return false;
    }

    public void setOnLongClickListener(@Nullable OnLongClickListener l) {
        
    }

    public boolean hasOnLongClickListeners() {
        return false;
    }

    @Nullable
    public OnLongClickListener getOnLongClickListener() {
        return null;
    }

    public void setOnContextClickListener(@Nullable OnContextClickListener l) {
        
    }

    public void setOnCreateContextMenuListener(OnCreateContextMenuListener l) {
        
    }

    public void addFrameMetricsListener(Window window,
            Window.OnFrameMetricsAvailableListener listener,
            Handler handler) {
        
    }

    public void removeFrameMetricsListener(
            Window.OnFrameMetricsAvailableListener listener) {
        
    }

    /** @hide */
    public void setNotifyAutofillManagerOnClick(boolean notify) {
        
    }

    // NOTE: other methods on View should not call this method directly, but performClickInternal()
    // instead, to guarantee that the autofill manager is notified when necessary (as subclasses
    // could extend this method without calling super.performClick()).
    public boolean performClick() {
        return false;
    }

    public boolean callOnClick() {
        return false;
    }

    public boolean performLongClick() {
        return false;
    }

    public boolean performLongClick(float x, float y) {
        return false;
    }

    public boolean performContextClick(float x, float y) {
        return false;
    }

    public boolean performContextClick() {
        return false;
    }

    protected boolean performButtonActionOnTouchDown(MotionEvent event) {
        return false;
    }

    public boolean showContextMenu() {
        return false;
    }

    public boolean showContextMenu(float x, float y) {
        return false;
    }

    public ActionMode startActionMode(ActionMode.Callback callback) {
        return null;
    }

    public ActionMode startActionMode(ActionMode.Callback callback, int type) {
        return null;
    }

    public void startActivityForResult(Intent intent, int requestCode) {
        
    }

    public boolean dispatchActivityResult(
            String who, int requestCode, int resultCode, Intent data) {
        return false;
    }

    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        // Do nothing.
    }

    public void setOnKeyListener(OnKeyListener l) {
        
    }

    public void setOnTouchListener(OnTouchListener l) {
        
    }

    public void setOnGenericMotionListener(OnGenericMotionListener l) {
        
    }

    public void setOnHoverListener(OnHoverListener l) {
        
    }

    public void setOnDragListener(OnDragListener l) {
        
    }

    void handleFocusGainInternal(@FocusRealDirection int direction, Rect previouslyFocusedRect) {
        
    }

    public final void setRevealOnFocusHint(boolean revealOnFocus) {
        
    }

    public final boolean getRevealOnFocusHint() {
        return false;
    }

    public void getHotspotBounds(Rect outRect) {
        
    }

    public boolean requestRectangleOnScreen(Rect rectangle) {
        return false;
    }

    public boolean requestRectangleOnScreen(Rect rectangle, boolean immediate) {
        return false;
    }

    public void clearFocus() {
        
    }

    public void clearFocusInternal(View focused, boolean propagate, boolean refocus) {
        
    }

    void notifyGlobalFocusCleared(View oldFocus) {
        
    }

    boolean rootViewRequestFocus() {
        return false;
    }

    void unFocus(View focused) {
        
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public boolean hasFocus() {
        
            return false;
}

    public boolean hasFocusable() {
        return false;
    }

    public boolean hasExplicitFocusable() {
        return false;
    }

    boolean hasFocusable(boolean allowAutoFocus, boolean dispatchExplicit) {
        return false;
    }

    @CallSuper
    protected void onFocusChanged(boolean gainFocus, @FocusDirection int direction,
            @Nullable Rect previouslyFocusedRect) {
        
    }

    /** @hide */
    public void notifyEnterOrExitForAutoFillIfNeeded(boolean enter) {
        
    }

    public void setAccessibilityPaneTitle(@Nullable CharSequence accessibilityPaneTitle) {
        
    }

    @Nullable
    public CharSequence getAccessibilityPaneTitle() {
        return null;
    }

    public void sendAccessibilityEvent(int eventType) {
        
    }

    @Deprecated
    public void announceForAccessibility(CharSequence text) {
        
    }

    public void sendAccessibilityEventInternal(int eventType) {
        
    }

    public void sendAccessibilityEventUnchecked(AccessibilityEvent event) {
        
    }

    public void sendAccessibilityEventUncheckedInternal(AccessibilityEvent event) {
        
    }

    public boolean dispatchPopulateAccessibilityEvent(AccessibilityEvent event) {
        return false;
    }

    public boolean dispatchPopulateAccessibilityEventInternal(AccessibilityEvent event) {
        return false;
    }

    @CallSuper
    public void onPopulateAccessibilityEvent(AccessibilityEvent event) {
        
    }

    public void onPopulateAccessibilityEventInternal(AccessibilityEvent event) {
        
    }

    @CallSuper
    public void onInitializeAccessibilityEvent(AccessibilityEvent event) {
        
    }

    public void onInitializeAccessibilityEventInternal(AccessibilityEvent event) {
        
    }

    public AccessibilityNodeInfo createAccessibilityNodeInfo() {
        return null;
    }

    public @Nullable AccessibilityNodeInfo createAccessibilityNodeInfoInternal() {
        return null;
    }

    @CallSuper
    public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
        
    }

    public void getBoundsOnScreen(Rect outRect) {
        
    }

    @TestApi
    public void getBoundsOnScreen(@NonNull Rect outRect, boolean clipToParent) {
        
    }

    public void getBoundsOnScreen(RectF outRect, boolean clipToParent) {
        
    }

    public void getBoundsInWindow(Rect outRect, boolean clipToParent) {
        
    }

    public void mapRectFromViewToScreenCoords(RectF rect, boolean clipToParent) {
        
    }

    public void mapRectFromViewToWindowCoords(RectF rect, boolean clipToParent) {
        
    }

    public CharSequence getAccessibilityClassName() {
        return null;
    }

    public void onProvideStructure(ViewStructure structure) {
        
    }

    public void onProvideAutofillStructure(ViewStructure structure, @AutofillFlags int flags) {
        
    }

    public void onProvideContentCaptureStructure(@NonNull ViewStructure structure, int flags) {
        
    }

    /** @hide */
    protected void onProvideStructure(@NonNull ViewStructure structure,
            @ViewStructureType int viewFor, int flags) {
        
    }

    public void onProvideVirtualStructure(ViewStructure structure) {
        
    }

    public void onProvideAutofillVirtualStructure(ViewStructure structure, int flags) {
        
    }

    // public void setOnReceiveContentListener(
    //         @SuppressLint("NullableCollection") @Nullable String[] mimeTypes,
    //         @Nullable OnReceiveContentListener listener) {
    //     
    // }

    // @Nullable
    // public ContentInfo performReceiveContent(@NonNull ContentInfo payload) {
    //     
    // }

    // @Nullable
    // public ContentInfo onReceiveContent(@NonNull ContentInfo payload) {
    //     
    // }

    @SuppressLint("NullableCollection")
    @Nullable
    public String[] getReceiveContentMimeTypes() {
        return null;
    }

    public void autofill(@SuppressWarnings("unused") AutofillValue value) {
    }

    public void autofill(@NonNull @SuppressWarnings("unused") SparseArray<AutofillValue> values) {
        
    }

    // public void onGetCredentialResponse(GetCredentialResponse response) {
    //     
    // }

    public void onGetCredentialException(String errorType, String errorMsg) {
        
    }

    public final AutofillId getAutofillId() {
        return null;
    }

    // @Nullable
    // public final GetCredentialRequest getPendingCredentialRequest() {
    //     
    // }

    // @Nullable
    // public final OutcomeReceiver<GetCredentialResponse,
    //         GetCredentialException> getPendingCredentialCallback() {
    //     
    // }

    public void setAutofillId(@Nullable AutofillId id) {
        
    }

    public void resetSubtreeAutofillIds() {
        
    }

    public @AutofillType int getAutofillType() {
        return 0;
    }

    @ViewDebug.ExportedProperty()
    @Nullable public String[] getAutofillHints() {
        
            return null;
}

    @TestApi
    public boolean isAutofilled() {
        return false;
    }

    public boolean hideAutofillHighlight() {
        return false;
    }

    @Nullable
    public AutofillValue getAutofillValue() {
        return null;
    }

    public @AutofillImportance int getImportantForAutofill() {
        return 0;
    }

    public void setImportantForAutofill(@AutofillImportance int mode) {
        
    }

    public final boolean isImportantForAutofill() {
        return false;
    }

    public final void setContentSensitivity(@ContentSensitivity int mode)  {
        
    }

    public @ContentSensitivity final int getContentSensitivity() {
        return 0;
    }

    public final boolean isContentSensitive() {
        return false;
    }

    public @ContentCaptureImportance int getImportantForContentCapture() {
        return 0;
    }

    public void setImportantForContentCapture(@ContentCaptureImportance int mode) {
        
    }

    public final boolean isImportantForContentCapture() {
        return false;
    }
    /** @hide */
    protected boolean getNotifiedContentCaptureAppeared() {
        return false;
    }


    public void setContentCaptureSession(@Nullable ContentCaptureSession contentCaptureSession) {
        
    }

    @Nullable
    public final ContentCaptureSession getContentCaptureSession() {
        return null;
    }

    final boolean isActivityDeniedForAutofillForUnimportantView() {
        return false;
    }

    final boolean isMatchingAutofillableHeuristics() {
        return false;
    }
    /** @hide */
    public boolean canNotifyAutofillEnterExitEvent() {
        return false;
    }

    public void dispatchProvideStructure(ViewStructure structure) {
        
    }

    public void dispatchProvideAutofillStructure(@NonNull ViewStructure structure,
            @AutofillFlags int flags) {
        
    }

    public void dispatchInitialProvideContentCaptureStructure() {
        
    }

    /** @hide */
    void dispatchProvideContentCaptureStructure() {
        
    }

    public void onInitializeAccessibilityNodeInfoInternal(AccessibilityNodeInfo info) {
        
    }


    public void addExtraDataToAccessibilityNodeInfo(
            @NonNull AccessibilityNodeInfo info, @NonNull String extraDataKey,
            @Nullable Bundle arguments) {
    }

    public boolean isVisibleToUserForAutofill(int virtualId) {
        return false;
    }

    public boolean isVisibleToUser() {
        return false;
    }

    protected boolean isVisibleToUser(Rect boundInView) {
        return false;
    }

    public AccessibilityDelegate getAccessibilityDelegate() {
        return null;
    }

    public void setAccessibilityDelegate(@Nullable AccessibilityDelegate delegate) {
        
    }

    public AccessibilityNodeProvider getAccessibilityNodeProvider() {
        return null;
    }

    public int getAccessibilityViewId() {
        return 0;
    }

    public int getAutofillViewId() {
        return 0;
    }

    public int getAccessibilityWindowId() {
        return 0;
    }

    @ViewDebug.ExportedProperty(category = "accessibility")
    public final @Nullable CharSequence getStateDescription() {
        
            return null;
}

    @ViewDebug.ExportedProperty(category = "accessibility")
    public CharSequence getContentDescription() {
        
            return null;
}

    @ViewDebug.ExportedProperty(category = "accessibility")
    @Nullable
    public CharSequence getSupplementalDescription() {
        
            return null;
}

    public void setStateDescription(@Nullable CharSequence stateDescription) {
        
    }

    public void setContentDescription(CharSequence contentDescription) {
        
    }

    public void setSupplementalDescription(@Nullable CharSequence supplementalDescription) {
        
    }

    public void setAccessibilityTraversalBefore(@IdRes int beforeId) {
        
    }

    @IdRes
    public int getAccessibilityTraversalBefore() {
        return 0;
    }

    public void setAccessibilityTraversalAfter(@IdRes int afterId) {
        
    }

    @IdRes
    public int getAccessibilityTraversalAfter() {
        return 0;
    }

    @IdRes
    @ViewDebug.ExportedProperty(category = "accessibility")
    public int getLabelFor() {
        
            return 0;
}

    public void setLabelFor(@IdRes int id) {
        
    }

    @CallSuper
    protected void onFocusLost() {
        
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public boolean isFocused() {
        
            return false;
}

    public View findFocus() {
        return null;
    }

    public boolean isScrollContainer() {
        return false;
    }

    public void setScrollContainer(boolean isScrollContainer) {
        
    }

    @Deprecated
    @DrawingCacheQuality
    public int getDrawingCacheQuality() {
        return 0;
    }

    @Deprecated
    public void setDrawingCacheQuality(@DrawingCacheQuality int quality) {
        
    }

    public boolean getKeepScreenOn() {
        return false;
    }

    public void setKeepScreenOn(boolean keepScreenOn) {
        
    }

    @IdRes
    public int getNextFocusLeftId() {
        return 0;
    }

    public void setNextFocusLeftId(@IdRes int nextFocusLeftId) {
        
    }

    @IdRes
    public int getNextFocusRightId() {
        return 0;
    }

    public void setNextFocusRightId(@IdRes int nextFocusRightId) {
        
    }

    @IdRes
    public int getNextFocusUpId() {
        return 0;
    }

    public void setNextFocusUpId(@IdRes int nextFocusUpId) {
        
    }

    @IdRes
    public int getNextFocusDownId() {
        return 0;
    }

    public void setNextFocusDownId(@IdRes int nextFocusDownId) {
        
    }

    @IdRes
    public int getNextFocusForwardId() {
        return 0;
    }

    public void setNextFocusForwardId(@IdRes int nextFocusForwardId) {
        
    }

    @IdRes
    public int getNextClusterForwardId() {
        return mNextClusterForwardId;
    }

    public void setNextClusterForwardId(@IdRes int nextClusterForwardId) {
        
    }

    public boolean isShown() {
        return false;
    }

    @Deprecated
    protected boolean fitSystemWindows(Rect insets) {
        return false;
    }

    public WindowInsets onApplyWindowInsets(WindowInsets insets) {
        return null;
    }

    public void setOnApplyWindowInsetsListener(OnApplyWindowInsetsListener listener) {
        
    }

    public WindowInsets dispatchApplyWindowInsets(WindowInsets insets) {
        return null;
    }

    public void setWindowInsetsAnimationCallback(
            @Nullable WindowInsetsAnimation.Callback callback) {
        
    }

    public boolean hasWindowInsetsAnimationCallback() {
        return false;
    }

    public void dispatchWindowInsetsAnimationPrepare(
            @NonNull WindowInsetsAnimation animation) {
        
    }

    @NonNull
    public Bounds dispatchWindowInsetsAnimationStart(
            @NonNull WindowInsetsAnimation animation, @NonNull Bounds bounds) {
        return null;
    }

    @NonNull
    public WindowInsets dispatchWindowInsetsAnimationProgress(@NonNull WindowInsets insets,
            @NonNull List<WindowInsetsAnimation> runningAnimations) {
        return null;
    }

    public void dispatchWindowInsetsAnimationEnd(@NonNull WindowInsetsAnimation animation) {
        
    }

    public void setSystemGestureExclusionRects(@NonNull List<Rect> rects) {
        
    }

    void updateSystemGestureExclusionRects() {
        
    }

    @NonNull
    public List<Rect> getSystemGestureExclusionRects() {
        return null;
    }

    public final void setPreferKeepClear(boolean preferKeepClear) {
        
    }

    public final boolean isPreferKeepClear() {
        return false;
    }

    public final void setPreferKeepClearRects(@NonNull List<Rect> rects) {
        
    }

    @NonNull
    public final List<Rect> getPreferKeepClearRects() {
        return null;
    }

    @SystemApi
    public final void setUnrestrictedPreferKeepClearRects(@NonNull List<Rect> rects) {
        
    }

    @SystemApi
    @NonNull
    public final List<Rect> getUnrestrictedPreferKeepClearRects() {
        return null;
    }

    void updateKeepClearRects() {
        
    }

    @NonNull
    List<Rect> collectPreferKeepClearRects() {
        return null;
    }

    @NonNull
    List<Rect> collectUnrestrictedPreferKeepClearRects() {
        return null;
    }

    public void setHandwritingBoundsOffsets(float offsetLeft, float offsetTop,
            float offsetRight, float offsetBottom) {
        
    }

    public float getHandwritingBoundsOffsetLeft() {
        return 0;
    }

    public float getHandwritingBoundsOffsetTop() {
        return 0;
    }

    public float getHandwritingBoundsOffsetRight() {
        return 0;
    }

    public float getHandwritingBoundsOffsetBottom() {
        return 0;
    }


    public void setHandwritingArea(@Nullable Rect rect) {
        
    }

    @Nullable
    public Rect getHandwritingArea() {
        return null;
    }

    void updateHandwritingArea() {
        
    }

    boolean shouldInitiateHandwriting() {
        return false;
    }

    public boolean shouldTrackHandwritingArea() {
        return false;
    }

    public void setHandwritingDelegatorCallback(@Nullable Runnable callback) {
        
    }

    @Nullable
    public Runnable getHandwritingDelegatorCallback() {
        return null;
    }

    public void setAllowedHandwritingDelegatePackage(@Nullable String allowedPackageName) {
        
    }

    @Nullable
    public String getAllowedHandwritingDelegatePackageName() {
        return null;
    }

    public void setIsHandwritingDelegate(boolean isHandwritingDelegate) {
        
    }

    public boolean isHandwritingDelegate() {
        return false;
    }

    public void setAllowedHandwritingDelegatorPackage(@Nullable String allowedPackageName) {
        
    }

    @Nullable
    public String getAllowedHandwritingDelegatorPackageName() {
        return null;
    }

    public void setHandwritingDelegateFlags(
            int flags) {
        
    }

    public int getHandwritingDelegateFlags() {
        return 0;
    }

    public void getLocationInSurface(@NonNull @Size(2) int[] location) {
        
    }

    public WindowInsets getRootWindowInsets() {
        return null;
    }

    public @Nullable WindowInsetsController getWindowInsetsController() {
        return null;
    }

    // @Nullable
    // public final OnBackInvokedDispatcher findOnBackInvokedDispatcher() {
    //     
    // }

    @Deprecated
    protected boolean computeFitSystemWindows(Rect inoutInsets, Rect outLocalInsets) {
        return false;
    }

    public WindowInsets computeSystemWindowInsets(WindowInsets in, Rect outLocalInsets) {
        return null;
    }

    protected boolean hasContentOnApplyWindowInsetsListener() {
        return false;
    }

    public void setFitsSystemWindows(boolean fitSystemWindows) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean getFitsSystemWindows() {
        return false;
    }

    /** @hide */
    public boolean fitsSystemWindows() {
        return false;
    }

    @Deprecated
    public void requestFitSystemWindows() {
        
    }

    public void requestApplyInsets() {
        
    }

    public void makeOptionalFitsSystemWindows() {
        
    }

    public void makeFrameworkOptionalFitsSystemWindows() {
        
    }

    public boolean isFrameworkOptionalFitsSystemWindows() {
        return false;
    }

    @ViewDebug.ExportedProperty(mapping = {
        @ViewDebug.IntToString(from = VISIBLE,   to = "VISIBLE"),
        @ViewDebug.IntToString(from = INVISIBLE, to = "INVISIBLE"),
        @ViewDebug.IntToString(from = GONE,      to = "GONE")
    })
    @Visibility
    public int getVisibility() {
        return 0;
    }

    public void setVisibility(@Visibility int visibility) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean isEnabled() {
        return false;
    }

    public void setEnabled(boolean enabled) {
        
    }

    public void setFocusable(boolean focusable) {
        
    }

    public void setFocusable(@Focusable int focusable) {
        
    }

    public void setFocusableInTouchMode(boolean focusableInTouchMode) {
        
    }

    public void setAutofillHints(@Nullable String... autofillHints) {
        
    }

    @TestApi
    public void setAutofilled(boolean isAutofilled, boolean hideHighlight) {
        
    }

    public void setSoundEffectsEnabled(boolean soundEffectsEnabled) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean isSoundEffectsEnabled() {
        return false;
    }

    public void setHapticFeedbackEnabled(boolean hapticFeedbackEnabled) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean isHapticFeedbackEnabled() {
        return false;
    }

    @ViewDebug.ExportedProperty(category = "layout", mapping = {
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_LTR,     to = "LTR"),
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_RTL,     to = "RTL"),
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_INHERIT, to = "INHERIT"),
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_LOCALE,  to = "LOCALE")
    })
    @LayoutDir
    public int getRawLayoutDirection() {
        return 0;
    }

    public void setLayoutDirection(@LayoutDir int layoutDirection) {
        
    }

    @ViewDebug.ExportedProperty(category = "layout", mapping = {
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_LTR, to = "RESOLVED_DIRECTION_LTR"),
        @ViewDebug.IntToString(from = LAYOUT_DIRECTION_RTL, to = "RESOLVED_DIRECTION_RTL")
    })
    @ResolvedLayoutDir
    public int getLayoutDirection() {
        return 0;
    }

    @ViewDebug.ExportedProperty(category = "layout")
    public boolean isLayoutRtl() {
        
            return false;
}

    @ViewDebug.ExportedProperty(category = "layout")
    public boolean hasTransientState() {
        
            return false;
}

    public void setHasTransientState(boolean hasTransientState) {
        
    }

    public void setHasTranslationTransientState(boolean hasTranslationTransientState) {
        
    }

    public boolean hasTranslationTransientState() {
        return false;
    }

    public void clearTranslationState() {
        
    }

    public boolean isAttachedToWindow() {
        return false;
    }

    public boolean isLaidOut() {
        return false;
    }

    boolean isLayoutValid() {
        return false;
    }

    public void setWillNotDraw(boolean willNotDraw) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean willNotDraw() {
        
            return false;
}

    @Deprecated
    public void setWillNotCacheDrawing(boolean willNotCacheDrawing) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    @Deprecated
    public boolean willNotCacheDrawing() {
        
            return false;
}

    @ViewDebug.ExportedProperty
    public boolean isClickable() {
        return false;
    }

    public void setClickable(boolean clickable) {
        
    }

    public void setAllowClickWhenDisabled(boolean clickableWhenDisabled) {
        
    }

    public boolean isLongClickable() {
        return false;
    }

    public void setLongClickable(boolean longClickable) {
        
    }

    public boolean isContextClickable() {
        return false;
    }

    public void setContextClickable(boolean contextClickable) {
        
    }

    public void setPressed(boolean pressed) {
        
    }

    protected void dispatchSetPressed(boolean pressed) {
    }

    @ViewDebug.ExportedProperty
    public boolean isPressed() {
        return false;
    }

    public boolean isAssistBlocked() {
        return false;
    }

    public void setAssistBlocked(boolean enabled) {
        
    }

    public boolean isSaveEnabled() {
        return false;
    }

    public void setSaveEnabled(boolean enabled) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean getFilterTouchesWhenObscured() {
        return false;
    }

    public void setFilterTouchesWhenObscured(boolean enabled) {
        
    }

    public boolean isSaveFromParentEnabled() {
        return false;
    }

    public void setSaveFromParentEnabled(boolean enabled) {
        
    }


    @ViewDebug.ExportedProperty(category = "focus")
    public final boolean isFocusable() {
        
            return false;
}

    @ViewDebug.ExportedProperty(mapping = {
            @ViewDebug.IntToString(from = NOT_FOCUSABLE, to = "NOT_FOCUSABLE"),
            @ViewDebug.IntToString(from = FOCUSABLE, to = "FOCUSABLE"),
            @ViewDebug.IntToString(from = FOCUSABLE_AUTO, to = "FOCUSABLE_AUTO")
            }, category = "focus")
    @Focusable
    public int getFocusable() {
        return 0;
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public final boolean isFocusableInTouchMode() {
        
            return false;
}

    public boolean isScreenReaderFocusable() {
        return false;
    }

    public void setScreenReaderFocusable(boolean screenReaderFocusable) {
        
    }

    public boolean isAccessibilityHeading() {
        return false;
    }

    public void setAccessibilityHeading(boolean isHeading) {
        
    }

    public View focusSearch(@FocusRealDirection int direction) {
        return null;
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public final boolean isKeyboardNavigationCluster() {
        
            return false;
}

    View findKeyboardNavigationCluster() {
        return null;
    }

    public void setKeyboardNavigationCluster(boolean isCluster) {
        
    }

    @TestApi
    public final void setFocusedInCluster() {
        
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public final boolean isFocusedByDefault() {
        
            return false;
}

    public void setFocusedByDefault(boolean isFocusedByDefault) {
        
    }

    boolean hasDefaultFocus() {
        return false;
    }

    public View keyboardNavigationClusterSearch(View currentCluster,
            @FocusDirection int direction) {
        return null;
    }

    public boolean dispatchUnhandledMove(View focused, @FocusRealDirection int direction) {
        return false;
    }

    public void setDefaultFocusHighlightEnabled(boolean defaultFocusHighlightEnabled) {
        
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public final boolean getDefaultFocusHighlightEnabled() {
        
            return false;
}

    View findUserSetNextFocus(View root, @FocusDirection int direction) {
        return null;
    }

    View findUserSetNextKeyboardNavigationCluster(View root, @FocusDirection int direction) {
        return null;
    }

    public ArrayList<View> getFocusables(@FocusDirection int direction) {
        return null;
    }

    public void addFocusables(ArrayList<View> views, @FocusDirection int direction) {
        
    }

    public void addFocusables(ArrayList<View> views, @FocusDirection int direction,
            @FocusableMode int focusableMode) {
        
    }

    public void addKeyboardNavigationClusters(
            @NonNull Collection<View> views,
            int direction) {
        
    }

    public void findViewsWithText(ArrayList<View> outViews, CharSequence searched,
            @FindViewFlags int flags) {
        
    }

    public ArrayList<View> getTouchables() {
        return null;
    }

    public void addTouchables(ArrayList<View> views) {
        
    }

    public boolean isAccessibilityFocused() {
        return false;
    }

    public boolean requestAccessibilityFocus() {
        return false;
    }

    public void clearAccessibilityFocus() {
        
    }

    void clearAccessibilityFocusNoCallbacks(int action) {
        
    }

    public final boolean requestFocus() {
        return requestFocus(View.FOCUS_DOWN);
    }

    @TestApi
    public boolean restoreFocusInCluster(@FocusRealDirection int direction) {
        return false;
    }

    @TestApi
    public boolean restoreFocusNotInCluster() {
        return false;
    }

    public boolean restoreDefaultFocus() {
        return false;
    }

    public final boolean requestFocus(int direction) {
        return false;
    }

    public boolean requestFocus(int direction, Rect previouslyFocusedRect) {
        return false;
    }

    void clearParentsWantFocus() {
        
    }

    public final boolean requestFocusFromTouch() {
        return false;
    }

    public int getImportantForAccessibility() {
        return 0;
    }

    public void setAccessibilityLiveRegion(int mode) {
        
    }

    public int getAccessibilityLiveRegion() {
        return 0;
    }

    public void setImportantForAccessibility(int mode) {
        
    }

    public boolean isImportantForAccessibility() {
        return false;
    }

    public ViewParent getParentForAccessibility() {
        return null;
    }

    /** @hide */
    @Nullable
    View getSelfOrParentImportantForA11y() {
        return null;
    }

    public void addChildrenForAccessibility(ArrayList<View> outChildren) {

    }

    public boolean includeForAccessibility() {
        return false;
    }

    public boolean includeForAccessibility(boolean forNodeTree) {
        return false;
    }

    @ViewDebug.ExportedProperty(category = "accessibility")
    public boolean isAccessibilityDataSensitive() {
        
            return false;
}

    void calculateAccessibilityDataSensitive() {
        
    }

    public void setAccessibilityDataSensitive(
            @AccessibilityDataSensitive int accessibilityDataSensitive) {
        
    }

    public boolean isActionableForAccessibility() {
        return false;
    }

    public void notifyViewAccessibilityStateChangedIfNeeded(int changeType) {
        
    }

    public void notifySubtreeAccessibilityStateChangedIfNeeded() {
        
    }

    public void setTransitionVisibility(@Visibility int visibility) {
        
    }

    void resetSubtreeAccessibilityStateChanged() {
        
    }

    public boolean dispatchNestedPrePerformAccessibilityAction(int action,
            @Nullable Bundle arguments) {
        return false;
    }

    public boolean performAccessibilityAction(int action, @Nullable Bundle arguments) {
        return false;
    }

    public boolean performAccessibilityActionInternal(int action, @Nullable Bundle arguments) {
        return false;
    }

    public CharSequence getIterableTextForAccessibility() {
        return null;
    }

    public boolean isAccessibilitySelectionExtendable() {
        return false;
    }

    public void prepareForExtendedAccessibilitySelection() {
        
    }

    public int getAccessibilitySelectionStart() {
        return 0;
    }

    public int getAccessibilitySelectionEnd() {
        return 0;
    }

    public void setAccessibilitySelection(int start, int end) {
        
    }

    // public TextSegmentIterator getIteratorForGranularity(int granularity) {
    //     
    // }

    public final boolean isTemporarilyDetached() {
        return false;
    }

    @CallSuper
    public void dispatchStartTemporaryDetach() {
        
    }

    public void onStartTemporaryDetach() {
        
    }

    @CallSuper
    public void dispatchFinishTemporaryDetach() {
        
    }

    public void onFinishTemporaryDetach() {
    }

    public KeyEvent.DispatcherState getKeyDispatcherState() {
        return null;
    }

    public boolean dispatchKeyEventPreIme(KeyEvent event) {
        return false;
    }

    public boolean dispatchKeyEvent(KeyEvent event) {
        return false;
    }

    public boolean dispatchKeyShortcutEvent(KeyEvent event) {
        return false;
    }

    public boolean dispatchTouchEvent(MotionEvent event) {
        return false;
    }

    boolean isAccessibilityFocusedViewOrHost() {
        return false;
    }

    protected boolean canReceivePointerEvents() {
        return false;
    }

    public boolean onFilterTouchEventForSecurity(MotionEvent event) {
        return false;
    }

    public boolean dispatchTrackballEvent(MotionEvent event) {
        return false;
    }

    public boolean dispatchCapturedPointerEvent(MotionEvent event) {
        return false;
    }

    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        return false;
    }

    protected boolean dispatchHoverEvent(MotionEvent event) {
        return false;
    }

    protected boolean hasHoveredChild() {
        return false;
    }

    protected boolean pointInHoveredChild(MotionEvent event) {
        return false;
    }

    protected boolean dispatchGenericPointerEvent(MotionEvent event) {
        return false;
    }

    protected boolean dispatchGenericFocusedEvent(MotionEvent event) {
        return false;
    }

    public final boolean dispatchPointerEvent(MotionEvent event) {
        return false;
    }

    public void dispatchWindowFocusChanged(boolean hasFocus) {
        
    }

    public void onWindowFocusChanged(boolean hasWindowFocus) {
        
    }

    public boolean hasWindowFocus() {
        return false;
    }

    public boolean hasImeFocus() {
        return false;
    }

    protected void dispatchVisibilityChanged(@NonNull View changedView,
            @Visibility int visibility) {
        
    }

    protected void onVisibilityChanged(@NonNull View changedView, @Visibility int visibility) {
    }

    public void dispatchDisplayHint(@Visibility int hint) {
        
    }

    protected void onDisplayHint(@Visibility int hint) {
    }

    public void dispatchWindowVisibilityChanged(@Visibility int visibility) {
        
    }

    protected void onWindowVisibilityChanged(@Visibility int visibility) {
        
    }

    public boolean isAggregatedVisible() {
        return false;
    }

    boolean dispatchVisibilityAggregated(boolean isVisible) {
        return false;
    }

    @CallSuper
    public void onVisibilityAggregated(boolean isVisible) {
        
    }

    @Visibility
    public int getWindowVisibility() {
        return 0;
    }

    public void getWindowVisibleDisplayFrame(Rect outRect) {
        
    }

    @TestApi
    public void getWindowDisplayFrame(@NonNull Rect outRect) {
        
    }

    public void dispatchConfigurationChanged(Configuration newConfig) {
        
    }

    protected void onConfigurationChanged(Configuration newConfig) {
    }

    // void dispatchCollectViewAttributes(AttachInfo attachInfo, int visibility) {
    //     
    // }

    // void performCollectViewAttributes(AttachInfo attachInfo, int visibility) {
    //     
    // }

    void needGlobalAttributesUpdate(boolean force) {
        
    }

    @ViewDebug.ExportedProperty
    public boolean isInTouchMode() {
        return false;
    }

    @ViewDebug.CapturedViewProperty
    public final Context getContext() {
        return mContext;
    }

    public boolean onKeyPreIme(int keyCode, KeyEvent event) {
        return false;
    }

    public boolean onKeyDown(int keyCode, KeyEvent event) {
        return false;
    }

    public boolean onKeyLongPress(int keyCode, KeyEvent event) {
        return false;
    }

    public boolean onKeyUp(int keyCode, KeyEvent event) {
        return false;
    }

    public boolean onKeyMultiple(int keyCode, int repeatCount, KeyEvent event) {
        return false;
    }

    public boolean onKeyShortcut(int keyCode, KeyEvent event) {
        return false;
    }

    public boolean onCheckIsTextEditor() {
        return false;
    }

    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
        return null;
    }

    public void onInputConnectionOpenedInternal(@NonNull InputConnection inputConnection,
            @NonNull EditorInfo editorInfo, @Nullable Handler handler) {}

    public void onInputConnectionClosedInternal() {}

    public boolean checkInputConnectionProxy(View view) {
        return false;
    }

    public void createContextMenu(ContextMenu menu) {
        
    }

    protected ContextMenuInfo getContextMenuInfo() {
        return null;
    }

    protected void onCreateContextMenu(ContextMenu menu) {
    }

    public boolean onTrackballEvent(MotionEvent event) {
        return false;
    }

    public boolean onGenericMotionEvent(MotionEvent event) {
        return false;
    }

    public boolean onHoverEvent(MotionEvent event) {
        return false;
    }

    @ViewDebug.ExportedProperty
    public boolean isHovered() {
        return false;
    }

    public void setHovered(boolean hovered) {
        
    }

    public void onHoverChanged(boolean hovered) {
    }

    protected boolean handleScrollBarDragging(MotionEvent event) {
        return false;
    }

    public boolean onTouchEvent(MotionEvent event) {
        return false;
    }

    public boolean isInScrollingContainer() {
        return false;
    }

    public void cancelLongPress() {
        
    }

    public void setTouchDelegate(TouchDelegate delegate) {
        
    }

    public TouchDelegate getTouchDelegate() {
        return null;
    }

    public final void requestUnbufferedDispatch(MotionEvent event) {
        
    }

    public final void requestUnbufferedDispatch(int source) {
        
    }

    void setFlags(int flags, int mask) {
        
    }

    public void bringToFront() {
        
    }

    void disableRotaryScrollFeedback() {
        
    }

    protected void onScrollChanged(int l, int t, int oldl, int oldt) {
        
    }

    public interface OnScrollChangeListener {
        void onScrollChange(View v, int scrollX, int scrollY, int oldScrollX, int oldScrollY);
    }

    public interface OnLayoutChangeListener {
        void onLayoutChange(View v, int left, int top, int right, int bottom,
            int oldLeft, int oldTop, int oldRight, int oldBottom);
    }

    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
    }

    protected void dispatchDraw(@NonNull Canvas canvas) {

    }

    public final ViewParent getParent() {
        return null;
    }

    public void setScrollX(int value) {
        
    }

    public void setScrollY(int value) {
        
    }

    public final int getScrollX() {
        return 0;
    }

    public final int getScrollY() {
        return 0;
    }

    @ViewDebug.ExportedProperty(category = "layout")
    public final int getWidth() {
        
            return 0;
}

    @ViewDebug.ExportedProperty(category = "layout")
    public final int getHeight() {
        
            return 0;
}

    public void getDrawingRect(Rect outRect) {
        
    }

    public final int getMeasuredWidth() {
        return 0;
    }

    public final int getMeasuredWidthAndState() {
        return 0;
    }

    public final int getMeasuredHeight() {
        return 0;
    }

    public final int getMeasuredHeightAndState() {
        return 0;
    }

    public final int getMeasuredState() {
        return 0;
    }

    public Matrix getMatrix() {
        return null;
    }

    public final boolean hasIdentityMatrix() {
        return false;
    }

    void ensureTransformationInfo() {
        
    }

    public final Matrix getInverseMatrix() {
        return null;
    }

    public float getCameraDistance() {
        return 0;
    }

    public void setCameraDistance(float distance) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getRotation() {
        
            return 0;
}

    public void setRotation(float rotation) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getRotationY() {
        
            return 0;
}

    public void setRotationY(float rotationY) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getRotationX() {
        
            return 0;
}

    public void setRotationX(float rotationX) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getScaleX() {
        
            return 0;
}

    public void setScaleX(float scaleX) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getScaleY() {
        
            return 0;
}

    public void setScaleY(float scaleY) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getPivotX() {
        
            return 0;
}

    public void setPivotX(float pivotX) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getPivotY() {
        
            return 0;
}

    public void setPivotY(float pivotY) {
        
    }

    public boolean isPivotSet() {
        return false;
    }

    public void resetPivot() {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getAlpha() {
        
            return 0;
}

    public void forceHasOverlappingRendering(boolean hasOverlappingRendering) {
        
    }

    public final boolean getHasOverlappingRendering() {
        return false;
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean hasOverlappingRendering() {
        
            return false;
}

    public void setAlpha(@FloatRange(from=0.0, to=1.0) float alpha) {
        
    }

    boolean setAlphaNoInvalidation(float alpha) {
        return false;
    }

    void setAlphaInternal(float alpha) {
        
    }

    public void setTransitionAlpha(float alpha) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getTransitionAlpha() {
        
            return 0;
}

    public void setForceDarkAllowed(boolean allow) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean isForceDarkAllowed() {
        
            return false;
}

    @ViewDebug.CapturedViewProperty
    public final int getTop() {
        return 0;
    }

    public final void setTop(int top) {
        
    }

    @ViewDebug.CapturedViewProperty
    public final int getBottom() {
        return 0;
    }

    public boolean isDirty() {
        return false;
    }

    public final void setBottom(int bottom) {
        
    }

    @ViewDebug.CapturedViewProperty
    public final int getLeft() {
        return 0;
    }

    public final void setLeft(int left) {
        
    }

    @ViewDebug.CapturedViewProperty
    public final int getRight() {
        return 0;
    }

    public final void setRight(int right) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getX() {
        
            return 0;
}

    public void setX(float x) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getY() {
        
            return 0;
}

    public void setY(float y) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getZ() {
        
            return 0;
}

    public void setZ(float z) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getElevation() {
        
            return 0;
}

    public void setElevation(float elevation) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getTranslationX() {
        
            return 0;
}

    public void setTranslationX(float translationX) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getTranslationY() {
        
            return 0;
}

    public void setTranslationY(float translationY) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public float getTranslationZ() {
        
            return 0;
}

    public void setTranslationZ(float translationZ) {
        
    }

    public void setAnimationMatrix(@Nullable Matrix matrix) {
        
    }

    @Nullable
    public Matrix getAnimationMatrix() {
        return null;
    }

    public StateListAnimator getStateListAnimator() {
        return null;
    }

    public void setStateListAnimator(StateListAnimator stateListAnimator) {
        
    }

    public final boolean getClipToOutline() {
        return false;
    }

    public void setClipToOutline(boolean clipToOutline) {
        
    }


    public void setOutlineProvider(ViewOutlineProvider provider) {
        
    }

    public ViewOutlineProvider getOutlineProvider() {
        return null;
    }

    public void invalidateOutline() {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean hasShadow() {
        
            return false;
}

    public void setOutlineSpotShadowColor(@ColorInt int color) {
        
    }

    public @ColorInt int getOutlineSpotShadowColor() {
        return 0;
    }

    public void setOutlineAmbientShadowColor(@ColorInt int color) {
        
    }

    public @ColorInt int getOutlineAmbientShadowColor() {
        return 0;
    }


    /** @hide */
    public void setRevealClip(boolean shouldClip, float x, float y, float radius) {
        
    }

    public void getHitRect(Rect outRect) {
        
    }

    /*package*/ final boolean pointInView(float localX, float localY) {
        return false;
    }

    public boolean pointInView(float localX, float localY, float slop) {
        return false;
    }

    public void getFocusedRect(Rect r) {
        
    }

    public boolean getGlobalVisibleRect(Rect r, Point globalOffset) {
        return false;
    }

    public final boolean getGlobalVisibleRect(Rect r) {
        return false;
    }

    public final boolean getLocalVisibleRect(Rect r) {
        return false;
    }

    public void offsetTopAndBottom(int offset) {
        
    }

    public void offsetLeftAndRight(int offset) {
        
    }

    @ViewDebug.ExportedProperty(deepExport = true, prefix = "layout_")
    public ViewGroup.LayoutParams getLayoutParams() {
        
            return null;
}

    public void setLayoutParams(ViewGroup.LayoutParams params) {
        
    }

    public void resolveLayoutParams() {
        
    }

    public void scrollTo(int x, int y) {
        
    }

    public void scrollBy(int x, int y) {
        
    }

    protected boolean awakenScrollBars() {
        return false;
    }

    protected boolean awakenScrollBars(int startDelay) {
        return false;
    }

    protected boolean awakenScrollBars(int startDelay, boolean invalidate) {
        return false;
    }

    @Deprecated
    public void invalidate(Rect dirty) {
        
    }

    @Deprecated
    public void invalidate(int l, int t, int r, int b) {
        
    }

    public void invalidate() {
        
    }

    public void invalidate(boolean invalidateCache) {
        
    }

    void invalidateInternal(int l, int t, int r, int b, boolean invalidateCache,
            boolean fullInvalidate) {
        
    }

    void invalidateViewProperty(boolean invalidateParent, boolean forceRedraw) {
        
    }

    protected void damageInParent() {
        
    }

    protected void invalidateParentCaches() {
        
    }

    protected void invalidateParentIfNeeded() {
        
    }

    protected void invalidateParentIfNeededAndWasQuickRejected() {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean isOpaque() {
        
            return false;
}

    protected void computeOpaqueFlags() {
        
    }

    protected boolean hasOpaqueScrollbars() {
        return false;
    }

    public Handler getHandler() {
        return null;
    }

    // public ViewRootImpl getViewRootImpl() {
    //     
    // }

    // public ThreadedRenderer getThreadedRenderer() {
    //     
    // }

    public boolean post(Runnable action) {
        return false;
    }

    public boolean postDelayed(Runnable action, long delayMillis) {
        return false;
    }

    public void postOnAnimation(Runnable action) {
        
    }

    public void postOnAnimationDelayed(Runnable action, long delayMillis) {
        
    }

    public boolean removeCallbacks(Runnable action) {
        return false;
    }

    public void postInvalidate() {
        
    }

    public void postInvalidate(int left, int top, int right, int bottom) {
        
    }

    public void postInvalidateDelayed(long delayMilliseconds) {
        
    }

    public void postInvalidateDelayed(long delayMilliseconds, int left, int top,
            int right, int bottom) {
        
    }

    public void postInvalidateOnAnimation() {
        
    }

    public void postInvalidateOnAnimation(int left, int top, int right, int bottom) {
        
    }

    public void computeScroll() {
    }

    public boolean isHorizontalFadingEdgeEnabled() {
        return false;
    }

    public void setHorizontalFadingEdgeEnabled(boolean horizontalFadingEdgeEnabled) {
        
    }

    public boolean isVerticalFadingEdgeEnabled() {
        return false;
    }

    public void setVerticalFadingEdgeEnabled(boolean verticalFadingEdgeEnabled) {
        
    }

    public int getFadingEdge() {
        return 0;
    }

    public int getFadingEdgeLength() {
        return 0;
    }

    protected float getTopFadingEdgeStrength() {
        return 0;
    }

    protected float getBottomFadingEdgeStrength() {
        return 0;
    }

    protected float getLeftFadingEdgeStrength() {
        return 0;
    }

    protected float getRightFadingEdgeStrength() {
        return 0;
    }

    public boolean isHorizontalScrollBarEnabled() {
        return false;
    }

    public void setHorizontalScrollBarEnabled(boolean horizontalScrollBarEnabled) {
        
    }

    public boolean isVerticalScrollBarEnabled() {
        return false;
    }

    public void setVerticalScrollBarEnabled(boolean verticalScrollBarEnabled) {
        
    }

    protected void recomputePadding() {
        
    }

    public void setScrollbarFadingEnabled(boolean fadeScrollbars) {
        
    }

    public boolean isScrollbarFadingEnabled() {
        return false;
    }

    public int getScrollBarDefaultDelayBeforeFade() {
        return 0;
    }

    public void setScrollBarDefaultDelayBeforeFade(int scrollBarDefaultDelayBeforeFade) {
        
    }

    public int getScrollBarFadeDuration() {
        return 0;
    }

    public void setScrollBarFadeDuration(int scrollBarFadeDuration) {
        
    }

    public int getScrollBarSize() {
        return 0;
    }

    public void setScrollBarSize(int scrollBarSize) {
        
    }

    public void setScrollBarStyle(@ScrollBarStyle int style) {
        
    }

    @ScrollBarStyle
    public int getScrollBarStyle() {
        return 0;
    }

    protected int computeHorizontalScrollRange() {
        return 0;
    }

    protected int computeHorizontalScrollOffset() {
        return 0;
    }

    protected int computeHorizontalScrollExtent() {
        return 0;
    }

    protected int computeVerticalScrollRange() {
        return 0;
    }

    protected int computeVerticalScrollOffset() {
        return 0;
    }

    protected int computeVerticalScrollExtent() {
        return 0;
    }

    public boolean canScrollHorizontally(int direction) {
        return false;
    }

    public boolean canScrollVertically(int direction) {
        return false;
    }

    void getScrollIndicatorBounds(@NonNull Rect out) {
        
    }

    protected final void onDrawScrollBars(@NonNull Canvas canvas) {
        
    }

    protected boolean isVerticalScrollBarHidden() {
        return false;
    }

    protected void onDrawHorizontalScrollBar(@NonNull Canvas canvas, Drawable scrollBar,
            int l, int t, int r, int b) {
        
    }

    protected void onDrawVerticalScrollBar(@NonNull Canvas canvas, Drawable scrollBar,
            int l, int t, int r, int b) {
        
    }

    protected void onDraw(@NonNull Canvas canvas) {
    }

    /*
     * Caller is responsible for calling requestLayout if necessary.
     * (This allows addViewInLayout to not request a new layout.)
     */
    void assignParent(ViewParent parent) {
        
    }

    @CallSuper
    protected void onAttachedToWindow() {
        
    }

    public boolean resolveRtlPropertiesIfNeeded() {
        return false;
    }

    @TestApi
    public void resetRtlProperties() {
        
    }

    void dispatchScreenStateChanged(int screenState) {
        
    }

    public void onScreenStateChanged(int screenState) {
    }

    void dispatchMovedToDisplay(Display display, Configuration config) {
        
    }

    public void onMovedToDisplay(int displayId, Configuration config) {
    }

    public void onRtlPropertiesChanged(@ResolvedLayoutDir int layoutDirection) {
    }

    public boolean resolveLayoutDirection() {
        return false;
    }

    public boolean canResolveLayoutDirection() {
        return false;
    }

    @TestApi
    public void resetResolvedLayoutDirection() {
        
    }

    public boolean isLayoutDirectionInherited() {
        return false;
    }

    public boolean isLayoutDirectionResolved() {
        return false;
    }

    boolean isPaddingResolved() {
        return false;
    }

    public void resolvePadding() {
        
    }

    @TestApi
    public void resetResolvedPadding() {
        
    }

    void resetResolvedPaddingInternal() {
        
    }

    @CallSuper
    protected void onDetachedFromWindow() {
    }

    @CallSuper
    protected void onDetachedFromWindowInternal() {
        
    }

    public IBinder getWindowToken() {
        return null;
    }

    public WindowId getWindowId() {
        return null;
    }

    public IBinder getApplicationWindowToken() {
        return null;
    }

    public Display getDisplay() {
        return null;
    }

    // /*package*/ IWindowSession getWindowSession() {
    //     
    // }

    // protected IWindow getWindow() {
    //     
    // }

    int combineVisibility(int vis1, int vis2) {
        return 0;
    }

    public void fakeFocusAfterAttachingToWindow() {
        
    }

    // void dispatchAttachedToWindow(AttachInfo info, int visibility) {
    //     
    // }

    void dispatchDetachedFromWindow() {
        
    }

    public final void cancelPendingInputEvents() {
        
    }

    void dispatchCancelPendingInputEvents() {
        
    }

    public void onCancelPendingInputEvents() {
        
    }

    public void saveHierarchyState(SparseArray<Parcelable> container) {
        
    }

    protected void dispatchSaveInstanceState(SparseArray<Parcelable> container) {
        
    }

    @CallSuper
    @Nullable protected Parcelable onSaveInstanceState() {
        return null;
    }

    public void restoreHierarchyState(SparseArray<Parcelable> container) {
        
    }

    protected void dispatchRestoreInstanceState(SparseArray<Parcelable> container) {
        
    }

    @CallSuper
    protected void onRestoreInstanceState(Parcelable state) {
        
    }

    public long getDrawingTime() {
        return 0;
    }

    public void setDuplicateParentStateEnabled(boolean enabled) {
        
    }

    public boolean isDuplicateParentStateEnabled() {
        return false;
    }

    public void setLayerType(@LayerType int layerType, @Nullable Paint paint) {
        
    }

    // public void setRenderEffect(@Nullable RenderEffect renderEffect) {
    //     
    // }

    // public void setBackdropRenderEffect(@Nullable RenderEffect renderEffect) {
    //     
    // }

    public void setLayerPaint(@Nullable Paint paint) {
        
    }

    @LayerType
    public int getLayerType() {
        return 0;
    }

    public void buildLayer() {
        
    }

    public boolean probablyHasInput() {
        return false;
    }

    @CallSuper
    protected void destroyHardwareResources() {
        
    }

    @Deprecated
    public void setDrawingCacheEnabled(boolean enabled) {
        
    }

    @Deprecated
    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean isDrawingCacheEnabled() {
        
            return false;
}

    @SuppressWarnings({"UnusedDeclaration"})
    public void outputDirtyFlags(String indent, boolean clear, int clearMask) {
        return;
    }

    protected void dispatchGetDisplayList() {}

    public boolean canHaveDisplayList() {
        return false;
    }

    @NonNull
    public RenderNode updateDisplayListIfDirty() {
        return null;
    }

    @Deprecated
    public Bitmap getDrawingCache() {
        return null;
    }

    @Deprecated
    public Bitmap getDrawingCache(boolean autoScale) {
        return null;
    }

    @Deprecated
    public void destroyDrawingCache() {
        
    }

    @Deprecated
    public void setDrawingCacheBackgroundColor(@ColorInt int color) {
        
    }

    @Deprecated
    @ColorInt
    public int getDrawingCacheBackgroundColor() {
        return 0;
    }

    @Deprecated
    public void buildDrawingCache() {
        
    }

    @Deprecated
    public void buildDrawingCache(boolean autoScale) {
        
    }

    // public Bitmap createSnapshot(ViewDebug.CanvasProvider canvasProvider, boolean skipChildren) {
    //     
    // }

    public boolean isInEditMode() {
        return false;
    }

    protected boolean isPaddingOffsetRequired() {
        return false;
    }

    protected int getLeftPaddingOffset() {
        return 0;
    }

    protected int getRightPaddingOffset() {
        return 0;
    }

    protected int getTopPaddingOffset() {
        return 0;
    }

    protected int getBottomPaddingOffset() {
        return 0;
    }

    protected int getFadeTop(boolean offsetRequired) {
        return 0;
    }

    protected int getFadeHeight(boolean offsetRequired) {
        return 0;
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean isHardwareAccelerated() {
        
            return false;
}

    public void setClipBounds(Rect clipBounds) {
        
    }

    public Rect getClipBounds() {
        return null;
    }


    public boolean getClipBounds(Rect outRect) {
        return false;
    }

    void setDisplayListProperties(RenderNode renderNode) {
        
    }

    protected final boolean drawsWithRenderNode(@NonNull Canvas canvas) {
        return false;
    }

    boolean draw(@NonNull Canvas canvas, ViewGroup parent, long drawingTime) {
        return false;
    }

    static Paint getDebugPaint() {
        return null;
    }

    final int dipsToPixels(int dips) {
        return 0;
    }

    @CallSuper
    public void draw(@NonNull Canvas canvas) {
        
    }

    void setBackgroundBounds() {
        
    }

    public ViewOverlay getOverlay() {
        return null;
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    @ColorInt
    public int getSolidColor() {
        return 0;
    }

    public boolean isLayoutRequested() {
        return false;
    }

    public static boolean isLayoutModeOptical(Object o) {
        return false;
    }

    public static void setTraceLayoutSteps(boolean traceLayoutSteps) {
        
    }

    public static void setTracedRequestLayoutClassClass(String s) {
        
    }

    @SuppressWarnings({"unchecked"})
    public void layout(int l, int t, int r, int b) {
        return;
    }

    protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
    }

    protected boolean setFrame(int left, int top, int right, int bottom) {
        return false;
    }

    public final void setLeftTopRightBottom(int left, int top, int right, int bottom) {
        
    }

    @CallSuper
    protected void onFinishInflate() {
    }

    public Resources getResources() {
        return null;
    }

    @Override
    public void invalidateDrawable(@NonNull Drawable drawable) {
        
    }

    @Override
    public void scheduleDrawable(@NonNull Drawable who, @NonNull Runnable what, long when) {
        
    }

    @Override
    public void unscheduleDrawable(@NonNull Drawable who, @NonNull Runnable what) {
        
    }

    public void unscheduleDrawable(Drawable who) {
        
    }

    protected void resolveDrawables() {
        
    }

    boolean areDrawablesResolved() {
        return false;
    }

    public void onResolveDrawables(@ResolvedLayoutDir int layoutDirection) {
    }

    @TestApi
    protected void resetResolvedDrawables() {
        
    }

    void resetResolvedDrawablesInternal() {
        
    }

    @CallSuper
    protected boolean verifyDrawable(@NonNull Drawable who) {
        return false;
    }

    @CallSuper
    protected void drawableStateChanged() {
        
    }

    @CallSuper
    public void drawableHotspotChanged(float x, float y) {
        
    }

    public void dispatchDrawableHotspotChanged(float x, float y) {
    }

    public void refreshDrawableState() {
        
    }

    @TestApi
    public boolean isDefaultFocusHighlightNeeded(Drawable background, Drawable foreground) {
        return false;
    }

    public final int[] getDrawableState() {
        return null;
    }

    protected int[] onCreateDrawableState(int extraSpace) {
        return null;
    }

    protected static int[] mergeDrawableStates(int[] baseState, int[] additionalState) {
        return null;
    }

    @CallSuper
    public void jumpDrawablesToCurrentState() {
        
    }

    public void setBackgroundColor(@ColorInt int color) {
        
    }

    public void setBackgroundResource(@DrawableRes int resid) {
        
    }

    public void setBackground(Drawable background) {
        
    }

    @Deprecated
    public void setBackgroundDrawable(Drawable background) {
        
    }

    public Drawable getBackground() {
        return null;
    }

    public void setBackgroundTintList(@Nullable ColorStateList tint) {
        
    }

    @Nullable
    public ColorStateList getBackgroundTintList() {
        return null;
    }

    public void setBackgroundTintMode(@Nullable PorterDuff.Mode tintMode) {
        
    }

    public void setBackgroundTintBlendMode(@Nullable BlendMode blendMode) {
        
    }

    @Nullable
    public PorterDuff.Mode getBackgroundTintMode() {
        return null;
    }

    public @Nullable BlendMode getBackgroundTintBlendMode() {
        return null;
    }

    public Drawable getForeground() {
        return null;
    }

    public void setForeground(Drawable foreground) {
        
    }

    public boolean isForegroundInsidePadding() {
        return false;
    }

    public int getForegroundGravity() {
        return 0;
    }

    public void setForegroundGravity(int gravity) {
        
    }

    public void setForegroundTintList(@Nullable ColorStateList tint) {
        
    }

    @Nullable
    public ColorStateList getForegroundTintList() {
        return null;
    }

    public void setForegroundTintMode(@Nullable PorterDuff.Mode tintMode) {
        
    }

    public void setForegroundTintBlendMode(@Nullable BlendMode blendMode) {
        
    }

    @Nullable
    public PorterDuff.Mode getForegroundTintMode() {
        return null;
    }

    public @Nullable BlendMode getForegroundTintBlendMode() {
        return null;
    }

    public void onDrawForeground(@NonNull Canvas canvas) {
        
    }

    public void setPadding(int left, int top, int right, int bottom) {
        
    }

    protected void internalSetPadding(int left, int top, int right, int bottom) {
        
    }

    public void setPaddingRelative(int start, int top, int end, int bottom) {
        
    }

    @LayoutRes
    public int getSourceLayoutResId() {
        return 0;
    }

    public int getPaddingTop() {
        return 0;
    }

    public int getPaddingBottom() {
        return 0;
    }

    public int getPaddingLeft() {
        return 0;
    }

    public int getPaddingStart() {
        return 0;
    }

    public int getPaddingRight() {
        return 0;
    }

    public int getPaddingEnd() {
        return 0;
    }

    public boolean isPaddingRelative() {
        return false;
    }

    Insets computeOpticalInsets() {
        return null;
    }

    public void resetPaddingToInitialValues() {
        
    }

    public Insets getOpticalInsets() {
        return null;
    }

    public void setOpticalInsets(Insets insets) {
        
    }

    public void setSelected(boolean selected) {
        
    }

    protected void dispatchSetSelected(boolean selected) {
    }

    @ViewDebug.ExportedProperty
    public boolean isSelected() {
        return false;
    }

    public void setActivated(boolean activated) {
        
    }

    protected void dispatchSetActivated(boolean activated) {
    }

    @ViewDebug.ExportedProperty
    public boolean isActivated() {
        return false;
    }

    public ViewTreeObserver getViewTreeObserver() {
        return null;
    }

    public View getRootView() {
        return null;
    }

    public boolean toGlobalMotionEvent(MotionEvent ev) {
        return false;
    }

    public boolean toLocalMotionEvent(MotionEvent ev) {
        return false;
    }

    public void transformMatrixToGlobal(@NonNull Matrix matrix) {
        
    }

    public void transformMatrixToLocal(@NonNull Matrix matrix) {
        
    }

    public void transformMatrixRootToLocal(@NonNull Matrix matrix) {
        
    }

    @ViewDebug.ExportedProperty(category = "layout", indexMapping = {
            @ViewDebug.IntToString(from = 0, to = "x"),
            @ViewDebug.IntToString(from = 1, to = "y")
    })
    public int[] getLocationOnScreen() {
        return null;
    }

    public void getLocationOnScreen(@Size(2) int[] outLocation) {
        
    }

    public void getLocationInWindow(@Size(2) int[] outLocation) {
        
    }

    /** @hide */
    public void transformFromViewToWindowSpace(@Size(2) int[] inOutLocation) {
        
    }

    protected <T extends View> T findViewTraversal(@IdRes int id) {
        return null;
    }

    protected <T extends View> T findViewWithTagTraversal(Object tag) {
        return null;
    }

    protected <T extends View> T findViewByPredicateTraversal(Predicate<View> predicate,
            View childToSkip) {
        return null;
    }

    // Strictly speaking this should be marked as @Nullable but the nullability of the return value
    // is deliberately left unspecified as idiomatically correct code can make assumptions either
    // way based on local context, e.g. layout specification.
    public final <T extends View> T findViewById(@IdRes int id) {
        return null;
    }

    @NonNull
    public final <T extends View> T requireViewById(@IdRes int id) {
        return null;
    }

    public <T extends View> T findViewByAccessibilityIdTraversal(int accessibilityId) {
        return null;
    }

    public <T extends View> T findViewByAutofillIdTraversal(int autofillId) {
        return null;
    }


    public void findAutofillableViewsByTraversal(@NonNull List<View> autofillableViews) {
        
    }

    public final <T extends View> T findViewWithTag(Object tag) {
        return null;
    }

    public final <T extends View> T findViewByPredicate(Predicate<View> predicate) {
        return null;
    }

    public final <T extends View> T findViewByPredicateInsideOut(
            View start, Predicate<View> predicate) {
        return null;
    }

    public void setId(@IdRes int id) {
        
    }

    @TestApi
    public void setIsRootNamespace(boolean isRoot) {
        
    }

    public boolean isRootNamespace() {
        return false;
    }

    @IdRes
    @ViewDebug.CapturedViewProperty
    public int getId() {
        return 0;
    }

    public long getUniqueDrawingId() {
        return 0;
    }

    @ViewDebug.ExportedProperty
    public Object getTag() {
        return null;
    }

    public void setTag(final Object tag) {
        
    }

    public Object getTag(int key) {
        return null;
    }

    public void setTag(int key, final Object tag) {
        
    }

    public void setTagInternal(int key, Object tag) {
        
    }

    public void debug() {
        
    }

    protected void debug(int depth) {
        
    }

    protected static String debugIndent(int depth) {
        return null;
    }

    @ViewDebug.ExportedProperty(category = "layout")
    public int getBaseline() {
        
            return 0;
}

    public boolean isInLayout() {
        return false;
    }

    @CallSuper
    public void requestLayout() {
        
    }

    public void forceLayout() {
        
    }

    public final void measure(int widthMeasureSpec, int heightMeasureSpec) {
        
    }

    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        
    }

    protected final void setMeasuredDimension(int measuredWidth, int measuredHeight) {
        
    }

    public static int combineMeasuredStates(int curState, int newState) {
        return 0;
    }

    public static int resolveSize(int size, int measureSpec) {
        return 0;
    }

    public static int resolveSizeAndState(int size, int measureSpec, int childMeasuredState) {
        return 0;
    }

    public static int getDefaultSize(int size, int measureSpec) {
        return 0;
    }

    protected int getSuggestedMinimumHeight() {
        return 0;
    }

    protected int getSuggestedMinimumWidth() {
        return 0;
    }

    public int getMinimumHeight() {
        return 0;
    }

    public void setMinimumHeight(int minHeight) {
        
    }

    public int getMinimumWidth() {
        return 0;
    }

    public void setMinimumWidth(int minWidth) {
        
    }

    public Animation getAnimation() {
        return null;
    }

    public void startAnimation(Animation animation) {
        
    }

    public void clearAnimation() {
        
    }

    public void setAnimation(Animation animation) {
        
    }

    @CallSuper
    protected void onAnimationStart() {
        
    }

    @CallSuper
    protected void onAnimationEnd() {
        
    }

    protected boolean onSetAlpha(int alpha) {
        return false;
    }

    public boolean gatherTransparentRegion(@Nullable Region region) {
        return false;
    }

    public void playSoundEffect(int soundConstant) {
        
    }

    public boolean performHapticFeedback(int feedbackConstant) {
        return false;
    }

    public boolean performHapticFeedback(int feedbackConstant, int flags) {
        return false;
    }

    public void performHapticFeedbackForInputDevice(int feedbackConstant, int inputDeviceId,
            int inputSource, int flags) {
        
    }

    @Deprecated
    public void setSystemUiVisibility(int visibility) {
        
    }

    @Deprecated
    public int getSystemUiVisibility() {
        return 0;
    }

    @Deprecated
    public int getWindowSystemUiVisibility() {
        return 0;
    }

    @Deprecated
    public void onWindowSystemUiVisibilityChanged(int visible) {
    }

    @Deprecated
    public void dispatchWindowSystemUiVisiblityChanged(int visible) {
        
    }

    @Deprecated
    public void setOnSystemUiVisibilityChangeListener(OnSystemUiVisibilityChangeListener l) {
        
    }

    @Deprecated
    public void dispatchSystemUiVisibilityChanged(int visibility) {
        
    }

    boolean updateLocalSystemUiVisibility(int localValue, int localChanges) {
        return false;
    }

    /** @hide */
    public void setDisabledSystemUiVisibility(int flags) {
        
    }

    public void onSystemBarAppearanceChanged(int appearance) {
    }

    public static class DragShadowBuilder {
        public DragShadowBuilder(View view) {
            
        }

        public DragShadowBuilder() {
            
        }

        @SuppressWarnings({"JavadocReference"})
        final public View getView() {
            return null;
        }

        public void onProvideShadowMetrics(Point outShadowSize, Point outShadowTouchPoint) {
            
        }

        public void onDrawShadow(@NonNull Canvas canvas) {
            
        }
    }

    @Deprecated
    public final boolean startDrag(ClipData data, DragShadowBuilder shadowBuilder,
                                   Object myLocalState, int flags) {
        return false;
    }

    public final boolean startDragAndDrop(ClipData data, DragShadowBuilder shadowBuilder,
            Object myLocalState, int flags) {
        return false;
    }

    static boolean hasActivityPendingIntents(ClipData data) {
        return false;
    }

    static void cleanUpPendingIntents(ClipData data) {
        
    }

    void setAccessibilityDragStarted(boolean started) {
        
    }

    public final void cancelDragAndDrop() {
        
    }

    public final void updateDragShadow(DragShadowBuilder shadowBuilder) {
        
    }

    public final boolean startMovingTask(float startX, float startY) {
        return false;
    }

    public void finishMovingTask() {
        
    }

    public boolean onDragEvent(DragEvent event) {
        return false;
    }

    // Dispatches ACTION_DRAG_ENTERED and ACTION_DRAG_EXITED events for pre-Nougat apps.
    boolean dispatchDragEnterExitInPreN(DragEvent event) {
        return false;
    }

    public boolean dispatchDragEvent(DragEvent event) {
        return false;
    }

    final boolean callDragEventHandler(DragEvent event) {
        return false;
    }

    boolean canAcceptDrag() {
        return false;
    }

    void sendWindowContentChangedAccessibilityEvent(int changeType) {
        
    }

    public void onCloseSystemDialogs(String reason) {
    }

    public void applyDrawableToTransparentRegion(Drawable dr, Region region) {
        
    }

    public static View inflate(Context context, @LayoutRes int resource, ViewGroup root) {
        return null;
    }

    @SuppressWarnings({"UnusedParameters"})
    protected boolean overScrollBy(int deltaX, int deltaY,
            int scrollX, int scrollY,
            int scrollRangeX, int scrollRangeY,
            int maxOverScrollX, int maxOverScrollY,
            boolean isTouchEvent) {
        return false;
    }

    protected void onOverScrolled(int scrollX, int scrollY,
            boolean clampedX, boolean clampedY) {
        // Intentionally empty.
    }

    public int getOverScrollMode() {
        return 0;
    }

    public void setOverScrollMode(int overScrollMode) {
        
    }

    public void setNestedScrollingEnabled(boolean enabled) {
        
    }

    public boolean isNestedScrollingEnabled() {
        return false;
    }

    public boolean startNestedScroll(int axes) {
        return false;
    }

    public void stopNestedScroll() {
        
    }

    public boolean hasNestedScrollingParent() {
        return false;
    }

    public boolean dispatchNestedScroll(int dxConsumed, int dyConsumed,
            int dxUnconsumed, int dyUnconsumed, @Nullable @Size(2) int[] offsetInWindow) {
        return false;
    }

    public boolean dispatchNestedPreScroll(int dx, int dy,
            @Nullable @Size(2) int[] consumed, @Nullable @Size(2) int[] offsetInWindow) {
        return false;
    }

    public boolean dispatchNestedFling(float velocityX, float velocityY, boolean consumed) {
        return false;
    }

    public boolean dispatchNestedPreFling(float velocityX, float velocityY) {
        return false;
    }

    protected float getVerticalScrollFactor() {
        return 0;
    }

    protected float getHorizontalScrollFactor() {
        return 0;
    }

    public int getRawTextDirection() {
        return 0;
    }

    public void setTextDirection(int textDirection) {
        
    }

    public int getTextDirection() {
        return 0;
    }

    public boolean resolveTextDirection() {
        return false;
    }

    public boolean canResolveTextDirection() {
        return false;
    }

    @TestApi
    public void resetResolvedTextDirection() {
        
    }

    public boolean isTextDirectionInherited() {
        return false;
    }

    public boolean isTextDirectionResolved() {
        return false;
    }

    @TextAlignment
    public int getRawTextAlignment() {
        return 0;
    }

    public void setTextAlignment(@TextAlignment int textAlignment) {
        
    }

    @TextAlignment
    public int getTextAlignment() {
        return 0;
    }

    public boolean resolveTextAlignment() {
        return false;
    }

    public boolean canResolveTextAlignment() {
        return false;
    }

    @TestApi
    public void resetResolvedTextAlignment() {
        
    }

    public boolean isTextAlignmentInherited() {
        return false;
    }

    public boolean isTextAlignmentResolved() {
        return false;
    }

    public static int generateViewId() {
        return 0;
    }

    public void captureTransitioningViews(List<View> transitioningViews) {
        
    }

    public void findNamedViews(Map<String, View> namedElements) {
        
    }

    public PointerIcon onResolvePointerIcon(MotionEvent event, int pointerIndex) {
        return null;
    }

    public void setPointerIcon(PointerIcon pointerIcon) {
        
    }

    public PointerIcon getPointerIcon() {
        return null;
    }

    public boolean hasPointerCapture() {
        return false;
    }

    public void requestPointerCapture() {
        
    }


    public void releasePointerCapture() {
        
    }

    @CallSuper
    public void onPointerCaptureChange(boolean hasCapture) {
    }

    public void dispatchPointerCaptureChanged(boolean hasCapture) {
        
    }

    public boolean onCapturedPointerEvent(MotionEvent event) {
        return false;
    }

    public interface OnCapturedPointerListener {
        boolean onCapturedPointer(View view, MotionEvent event);
    }

    public void setOnCapturedPointerListener(OnCapturedPointerListener l) {
        
    }

    // Properties
    //
    public static final Property<View, Float> ALPHA = null;

    public static final Property<View, Float> TRANSLATION_X = null;

    public static final Property<View, Float> TRANSLATION_Y = null;

    public static final Property<View, Float> TRANSLATION_Z = null;

    public static final Property<View, Float> X = null;

    public static final Property<View, Float> Y = null;

    public static final Property<View, Float> Z = null;

    public static final Property<View, Float> ROTATION = null;

    public static final Property<View, Float> ROTATION_X = null;

    public static final Property<View, Float> ROTATION_Y = null;

    public static final Property<View, Float> SCALE_X = null;

    public static final Property<View, Float> SCALE_Y = null;

    public static class MeasureSpec {
        private static final int MODE_SHIFT = 30;

        /** @hide */
        @Retention(RetentionPolicy.SOURCE)
        public @interface MeasureSpecMode {}

        public static final int UNSPECIFIED = 0 << MODE_SHIFT;

        public static final int EXACTLY     = 1 << MODE_SHIFT;

        public static final int AT_MOST     = 2 << MODE_SHIFT;

        public static int makeMeasureSpec(@IntRange(from = 0, to = (1 << MeasureSpec.MODE_SHIFT) - 1) int size,
                                          @MeasureSpecMode int mode) {
            return 0;
        }

        public static int makeSafeMeasureSpec(int size, int mode) {
            return 0;
        }

        @MeasureSpecMode
        public static int getMode(int measureSpec) {
            return 0;
        }

        public static int getSize(int measureSpec) {
            return 0;
        }

        static int adjust(int measureSpec, int delta) {
            return 0;
        }

        public static String toString(int measureSpec) {
            return null;
        }
    }

    public ViewPropertyAnimator animate() {
        return null;
    }

    public final void setTransitionName(String transitionName) {
        
    }

    @ViewDebug.ExportedProperty
    public String getTransitionName() {
        return null;
    }

    public void requestKeyboardShortcuts(List<KeyboardShortcutGroup> data, int deviceId) {
        // Do nothing.
    }

    public interface OnKeyListener {
        boolean onKey(View v, int keyCode, KeyEvent event);
    }

    public interface OnUnhandledKeyEventListener {
        boolean onUnhandledKeyEvent(View v, KeyEvent event);
    }

    public interface OnTouchListener {
        boolean onTouch(View v, MotionEvent event);
    }

    public interface OnHoverListener {
        boolean onHover(View v, MotionEvent event);
    }

    public interface OnGenericMotionListener {
        boolean onGenericMotion(View v, MotionEvent event);
    }

    public interface OnLongClickListener {
        boolean onLongClick(View v);

        default boolean onLongClickUseDefaultHapticFeedback(@NonNull View v) {
            return true;
        }
    }

    public interface OnDragListener {
        boolean onDrag(View v, DragEvent event);
    }

    public interface OnFocusChangeListener {
        void onFocusChange(View v, boolean hasFocus);
    }

    public interface OnClickListener {
        void onClick(View v);
    }

    public interface OnContextClickListener {
        boolean onContextClick(View v);
    }

    public interface OnCreateContextMenuListener {
        void onCreateContextMenu(ContextMenu menu, View v, ContextMenuInfo menuInfo);
    }

    @Deprecated
    public interface OnSystemUiVisibilityChangeListener {
        public void onSystemUiVisibilityChange(int visibility);
    }

    public interface OnAttachStateChangeListener {
        public void onViewAttachedToWindow(@NonNull View v);
        public void onViewDetachedFromWindow(@NonNull View v);
    }

    public interface OnApplyWindowInsetsListener {
        public @NonNull WindowInsets onApplyWindowInsets(@NonNull View v,
                @NonNull WindowInsets insets);
    }

    public static class BaseSavedState extends AbsSavedState {
        static final int START_ACTIVITY_REQUESTED_WHO_SAVED = 0b1;
        static final int IS_AUTOFILLED = 0b10;
        static final int AUTOFILL_ID = 0b100;

        // Flags that describe what data in this state is valid
        int mSavedData;
        String mStartActivityRequestWhoSaved;
        boolean mIsAutofilled;
        boolean mHideHighlight;
        int mAutofillViewId;

        public BaseSavedState(Parcel source) {
            this(source, null);
        }

        public BaseSavedState(Parcel source, ClassLoader loader) {
            super(source, loader);
            mSavedData = source.readInt();
            mStartActivityRequestWhoSaved = source.readString();
            mIsAutofilled = source.readBoolean();
            mHideHighlight = source.readBoolean();
            mAutofillViewId = source.readInt();
        }

        public BaseSavedState(Parcelable superState) {
            super(superState);
        }

        @Override
        public void writeToParcel(Parcel out, int flags) {
            super.writeToParcel(out, flags);

            out.writeInt(mSavedData);
            out.writeString(mStartActivityRequestWhoSaved);
            out.writeBoolean(mIsAutofilled);
            out.writeBoolean(mHideHighlight);
            out.writeInt(mAutofillViewId);
        }

        public static final @NonNull Parcelable.Creator<BaseSavedState> CREATOR
                = new Parcelable.ClassLoaderCreator<BaseSavedState>() {
            @Override
            public BaseSavedState createFromParcel(Parcel in) {
                return new BaseSavedState(in);
            }

            @Override
            public BaseSavedState createFromParcel(Parcel in, ClassLoader loader) {
                return new BaseSavedState(in, loader);
            }

            @Override
            public BaseSavedState[] newArray(int size) {
                return new BaseSavedState[size];
            }
        };
    }

    public static class AccessibilityDelegate {

        public void sendAccessibilityEvent(@NonNull View host, int eventType) {
            
        }

        public boolean performAccessibilityAction(@NonNull View host, int action,
                @Nullable Bundle args) {
            return false;
        }

        public void sendAccessibilityEventUnchecked(@NonNull View host,
                @NonNull AccessibilityEvent event) {
            
        }

        public boolean dispatchPopulateAccessibilityEvent(@NonNull View host,
                @NonNull AccessibilityEvent event) {
            return false;
        }

        public void onPopulateAccessibilityEvent(@NonNull View host,
                @NonNull AccessibilityEvent event) {
            
        }

        public void onInitializeAccessibilityEvent(@NonNull View host,
                @NonNull AccessibilityEvent event) {
            
        }

        public void onInitializeAccessibilityNodeInfo(@NonNull View host,
                @NonNull AccessibilityNodeInfo info) {
            
        }

        public void addExtraDataToAccessibilityNodeInfo(@NonNull View host,
                @NonNull AccessibilityNodeInfo info, @NonNull String extraDataKey,
                @Nullable Bundle arguments) {
            
        }

        public boolean onRequestSendAccessibilityEvent(@NonNull ViewGroup host, @NonNull View child,
                @NonNull AccessibilityEvent event) {
            return false;
        }

        public @Nullable AccessibilityNodeProvider getAccessibilityNodeProvider(
                @NonNull View host) {
            return null;
        }

        public AccessibilityNodeInfo createAccessibilityNodeInfo(@NonNull View host) {
            return null;
        }
    }

    @ScrollCaptureHint
    public int getScrollCaptureHint() {
        return 0;
    }

    public void setScrollCaptureHint(@ScrollCaptureHint int hint) {
        
    }

    // public final void setScrollCaptureCallback(@Nullable ScrollCaptureCallback callback) {
    //     
    // }

    // /** {@hide} */
    // @Nullable
    // public ScrollCaptureCallback createScrollCaptureCallbackInternal(@NonNull Rect localVisibleRect,
    //         @NonNull Point windowOffset) {
    //     
    // }

    // public void dispatchScrollCaptureSearch(
    //         @NonNull Rect localVisibleRect, @NonNull Point windowOffset,
    //         @NonNull Consumer<ScrollCaptureTarget> targets) {
    //     
    // }

    // public void onScrollCaptureSearch(@NonNull Rect localVisibleRect,
    //         @NonNull Point windowOffset, @NonNull Consumer<ScrollCaptureTarget> targets) {
    //     
    // }

    // /** {@hide} */
    // public void encode(@NonNull ViewHierarchyEncoder stream) {
    //     
    // }

    // /** {@hide} */
    // @CallSuper
    // protected void encodeProperties(@NonNull ViewHierarchyEncoder stream) {
    //     
    // }

    boolean shouldDrawRoundScrollbar() {
        return false;
    }

    public void setTooltipText(@Nullable CharSequence tooltipText) {
        
    }

    public void setTooltip(@Nullable CharSequence tooltipText) {
        
    }

    @Nullable
    public CharSequence getTooltipText() {
        return null;
    }

    @Nullable
    public CharSequence getTooltip() {
        return null;
    }

    void hideTooltip() {
        
    }

    boolean dispatchTooltipHoverEvent(MotionEvent event) {
        return false;
    }

    void handleTooltipKey(KeyEvent event) {
        
    }

    @TestApi
    public View getTooltipView() {
        return null;
    }

    @TestApi
    public static boolean isDefaultFocusHighlightEnabled() {
        return false;
    }

    View dispatchUnhandledKeyEvent(KeyEvent evt) {
        return null;
    }

    boolean onUnhandledKeyEvent(@NonNull KeyEvent event) {
        return false;
    }

    boolean hasUnhandledKeyListener() {
        return false;
    }

    public void addOnUnhandledKeyEventListener(OnUnhandledKeyEventListener listener) {
        
    }

    public void removeOnUnhandledKeyEventListener(OnUnhandledKeyEventListener listener) {
        
    }

    protected void setDetached(boolean detached) {
        
    }

    public void setIsCredential(boolean isCredential) {
        
    }

    public boolean isCredential() {
        return false;
    }

    // TODO(316208691): Revive following removed API docs.
    // @see EditorInfo#setStylusHandwritingEnabled(boolean)
    public void setAutoHandwritingEnabled(boolean enabled) {
        
    }

    public boolean isAutoHandwritingEnabled() {
        return false;
    }

    public boolean isStylusHandwritingAvailable() {
        return false;
    }

    // public void onCreateViewTranslationRequest(@NonNull int[] supportedFormats,
    //         @NonNull Consumer<ViewTranslationRequest> requestsCollector) {
    // }

    // @SuppressLint("NullableCollection")
    // public void onCreateVirtualViewTranslationRequests(@NonNull long[] virtualIds,
    //         @NonNull int[] supportedFormats,
    //         @NonNull Consumer<ViewTranslationRequest> requestsCollector) {
    //     // no-op
    // }

    // @Nullable
    // public ViewTranslationCallback getViewTranslationCallback() {
    //     
    // }

    // public void setViewTranslationCallback(@NonNull ViewTranslationCallback callback) {
    //     
    // }

    // public void clearViewTranslationCallback() {
    //     
    // }

    // @Nullable
    // public ViewTranslationResponse getViewTranslationResponse() {
    //     
    // }

    // public void onViewTranslationResponse(@NonNull ViewTranslationResponse response) {
    //     
    // }

    // public void clearViewTranslationResponse() {
    //     
    // }

    // public void onVirtualViewTranslationResponses(
    //         @NonNull LongSparseArray<ViewTranslationResponse> response) {
    //     // no-op
    // }

    // public void dispatchCreateViewTranslationRequest(@NonNull Map<AutofillId, long[]> viewIds,
    //         @NonNull int[] supportedFormats,
    //         @NonNull TranslationCapability capability,
    //         @NonNull List<ViewTranslationRequest> requests) {
    //     
    // }

    // public void generateDisplayHash(@NonNull String hashAlgorithm,
    //         @Nullable Rect bounds, @NonNull Executor executor,
    //         @NonNull DisplayHashResultCallback callback) {
    //     
    // }

    /**
     * The AttachedSurfaceControl itself is not a View, it is just the interface to the
     * windowing-system object that contains the entire view hierarchy.
     * For the root View of a given hierarchy see {@link #getRootView}.

     * @return The {@link android.view.AttachedSurfaceControl} interface for this View.
     * This will only return a non-null value when called between {@link #onAttachedToWindow}
     * and {@link #onDetachedFromWindow}.
     */
    // public @Nullable AttachedSurfaceControl getRootSurfaceControl() {
    //     return null;
    // }

    protected int calculateFrameRateCategory() {
        return 0;
    }

    protected void votePreferredFrameRate() {
        
    }

    public void setFrameContentVelocity(float pixelsPerSecond) {
        
    }

    public float getFrameContentVelocity() {
        return 0;
    }

    public void setRequestedFrameRate(float frameRate) {
        
    }

    public float getRequestedFrameRate() {
        return 0;
    }

    void overrideFrameRate(float frameRate, boolean forceOverride) {
        
    }

    void setForcedOverrideFrameRateFlag(boolean forcedOverride) {
        
    }

    boolean getForcedOverrideFrameRateFlag() {
        return false;
    }

    void setSelfRequestedFrameRateFlag(boolean forcedOverride) {
        
    }

    boolean getSelfRequestedFrameRateFlag() {
        return false;
    }

    // public void reportAppJankStats(@NonNull AppJankStats appJankStats) {
    //     
    // }

    // public @Nullable JankTracker getJankTracker() {
    //     
    // }
}
