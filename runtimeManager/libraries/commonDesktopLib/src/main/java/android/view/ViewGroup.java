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

import android.animation.LayoutTransition;
import android.annotation.CallSuper;
import android.annotation.IdRes;
import android.annotation.NonNull;
import android.annotation.Nullable;
import android.annotation.TestApi;
import android.annotation.UiThread;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.content.res.TypedArray;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Point;
import android.graphics.PointF;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Region;
import android.os.Build;
import android.os.Bundle;
import android.os.Parcelable;
import android.os.SystemClock;
import android.util.AttributeSet;
import android.util.Log;
import android.util.SparseArray;
import android.view.WindowInsetsAnimation.Bounds;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.animation.Animation;
import android.view.animation.AnimationUtils;
import android.view.animation.LayoutAnimationController;
import android.view.animation.Transformation;
import android.view.autofill.AutofillId;
import android.view.autofill.AutofillManager;
import android.webkit.WebView;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.Predicate;

@UiThread
public abstract class ViewGroup extends View implements ViewParent, ViewManager {
    protected ArrayList<View> mDisappearingChildren;

    protected OnHierarchyChangeListener mOnHierarchyChangeListener;

    // The last child of this ViewGroup which held focus within the current cluster
    View mFocusedInCluster;

    RectF mInvalidateRegion;

    Transformation mInvalidationTransformation;

    protected int mGroupFlags;


    // When set, ViewGroup invalidates only the child's rectangle
    // Set by default
    static final int FLAG_CLIP_CHILDREN = 0x1;

    // When set, dispatchDraw() will invoke invalidate(); this is set by drawChild() when
    // a child needs to be invalidated and FLAG_OPTIMIZE_INVALIDATE is set
    static final int FLAG_INVALIDATE_REQUIRED  = 0x4;

    // When set, there is either no layout animation on the ViewGroup or the layout
    // animation is over
    // Set by default
    static final int FLAG_ANIMATION_DONE = 0x10;

    // When set, this ViewGroup converts calls to invalidate(Rect) to invalidate() during a
    // layout animation; this avoid clobbering the hierarchy
    // Automatically set when the layout animation starts, depending on the animation's
    // characteristics
    static final int FLAG_OPTIMIZE_INVALIDATE = 0x80;

    // When set, the next call to drawChild() will clear mChildTransformation's matrix
    static final int FLAG_CLEAR_TRANSFORMATION = 0x100;

    protected static final int FLAG_USE_CHILD_DRAWING_ORDER = 0x400;

    protected static final int FLAG_SUPPORT_STATIC_TRANSFORMATIONS = 0x800;

    // UNUSED FLAG VALUE: 0x1000;

    public static final int FOCUS_BEFORE_DESCENDANTS = 0x20000;

    public static final int FOCUS_AFTER_DESCENDANTS = 0x40000;

    public static final int FOCUS_BLOCK_DESCENDANTS = 0x60000;

    protected static final int FLAG_DISALLOW_INTERCEPT = 0x80000;

    static final int FLAG_IS_TRANSITION_GROUP = 0x1000000;

    static final int FLAG_IS_TRANSITION_GROUP_SET = 0x2000000;

    static final int FLAG_TOUCHSCREEN_BLOCKS_FOCUS = 0x4000000;

    protected int mPersistentDrawingCache;

    @Deprecated
    public static final int PERSISTENT_NO_CACHE = 0x0;

    @Deprecated
    public static final int PERSISTENT_ANIMATION_CACHE = 0x1;

    @Deprecated
    public static final int PERSISTENT_SCROLLING_CACHE = 0x2;

    @Deprecated
    public static final int PERSISTENT_ALL_CACHES = 0x3;

    // Layout Modes

    public static final int LAYOUT_MODE_CLIP_BOUNDS = 0;

    public static final int LAYOUT_MODE_OPTICAL_BOUNDS = 1;

    /** @hide */
    public static int LAYOUT_MODE_DEFAULT = LAYOUT_MODE_CLIP_BOUNDS;

    protected static final int CLIP_TO_PADDING_MASK = 0;

    // Whether layout calls are currently being suppressed, controlled by calls to
    // suppressLayout()
    boolean mSuppressLayout = false;

    // Used to draw cached views
    Paint mCachePaint;

    int mChildUnhandledKeyListeners = 0;

    public ViewGroup(Context context) {
        this(context, null);
    }

    public ViewGroup(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public ViewGroup(Context context, AttributeSet attrs, int defStyleAttr) {
        this(context, attrs, defStyleAttr, 0);
    }

    public ViewGroup(Context context, AttributeSet attrs, int defStyleAttr, int defStyleRes) {
        super(context, attrs, defStyleAttr, defStyleRes);
    }

    public int getDescendantFocusability() {
        return 0;
    }

    public void setDescendantFocusability(int focusability) {
        
    }

    @Override
    void handleFocusGainInternal(int direction, Rect previouslyFocusedRect) {
        
    }

    @Override
    public void requestChildFocus(View child, View focused) {
        
    }

    void setDefaultFocus(View child) {
        
    }

    void clearDefaultFocus(View child) {
        
    }

    @Override
    boolean hasDefaultFocus() {
        return false;
    }

    void clearFocusedInCluster(View child) {
        
    }

    void clearFocusedInCluster() {
        
    }

    @Override
    public void focusableViewAvailable(View v) {
        
    }

    @Override
    public boolean showContextMenuForChild(View originalView) {
        return false;
    }

    public final boolean isShowingContextMenuWithCoords() {
        return false;
    }

    @Override
    public boolean showContextMenuForChild(View originalView, float x, float y) {
        return false;
    }

    @Override
    public ActionMode startActionModeForChild(View originalView, ActionMode.Callback callback) {
        return null;
    }

    @Override
    public ActionMode startActionModeForChild(
            View originalView, ActionMode.Callback callback, int type) {
        return null;
    }

    @Override
    public boolean dispatchActivityResult(
            String who, int requestCode, int resultCode, Intent data) {
        return false;
    }

    @Override
    public View focusSearch(View focused, int direction) {
        return null;
    }

    @Override
    public boolean requestChildRectangleOnScreen(View child, Rect rectangle, boolean immediate) {
        return false;
    }

    @Override
    public boolean requestSendAccessibilityEvent(View child, AccessibilityEvent event) {
        return false;
    }

    public boolean onRequestSendAccessibilityEvent(View child, AccessibilityEvent event) {
        return false;
    }

    public boolean onRequestSendAccessibilityEventInternal(View child, AccessibilityEvent event) {
        return true;
    }

    @Override
    public void childHasTransientStateChanged(View child, boolean childHasTransientState) {
        
    }

    @Override
    public boolean hasTransientState() {
        return false;
    }

    @Override
    public boolean dispatchUnhandledMove(View focused, int direction) {
        return false;
    }

    @Override
    public void clearChildFocus(View child) {
        
    }

    @Override
    public void clearFocus() {
        
    }

    @Override
    void unFocus(View focused) {
        
    }

    public View getFocusedChild() {
        return null;
    }

    View getDeepestFocusedChild() {
        return null;
    }

    @Override
    public boolean hasFocus() {
        return false;
    }

    /*
     * (non-Javadoc)
     *
     * @see android.view.View#findFocus()
     */
    @Override
    public View findFocus() {
        return null;
    }

    @Override
    boolean hasFocusable(boolean allowAutoFocus, boolean dispatchExplicit) {
        return false;
    }

    boolean hasFocusableChild(boolean dispatchExplicit) {
        return false;
    }

    @Override
    public void addFocusables(ArrayList<View> views, int direction, int focusableMode) {
        
    }

    @Override
    public void addKeyboardNavigationClusters(Collection<View> views, int direction) {
        
    }

    public void setTouchscreenBlocksFocus(boolean touchscreenBlocksFocus) {
        
    }

    @ViewDebug.ExportedProperty(category = "focus")
    public boolean getTouchscreenBlocksFocus() {
        return false;
    }

    boolean shouldBlockFocusForTouchscreen() {
        return false;
    }

    @Override
    public void findViewsWithText(ArrayList<View> outViews, CharSequence text, int flags) {
        
    }

    /** @hide */
    @Override
    public View findViewByAccessibilityIdTraversal(int accessibilityId) {
        return null;
    }

    /** @hide */
    @Override
    public View findViewByAutofillIdTraversal(int autofillId) {
        return null;
    }

    /** @hide */
    @Override
    public void findAutofillableViewsByTraversal(@NonNull List<View> autofillableViews) {
        
    }

    @Override
    public void dispatchWindowFocusChanged(boolean hasFocus) {
        
    }

    @Override
    public void addTouchables(ArrayList<View> views) {
        
    }

    @Override
    public void makeOptionalFitsSystemWindows() {
        
    }

    @Override
    public void makeFrameworkOptionalFitsSystemWindows() {
        
    }

    @Override
    public void dispatchDisplayHint(int hint) {
        
    }

    protected void onChildVisibilityChanged(View child, int oldVisibility, int newVisibility) {
        
    }

    @Override
    protected void dispatchVisibilityChanged(View changedView, int visibility) {
        
    }

    @Override
    public void dispatchWindowVisibilityChanged(int visibility) {
        
    }

    @Override
    boolean dispatchVisibilityAggregated(boolean isVisible) {
        return false;
    }

    @Override
    public void dispatchConfigurationChanged(Configuration newConfig) {
        
    }

    @Override
    public void recomputeViewAttributes(View child) {
        
    }

    // @Override
    // void dispatchCollectViewAttributes(AttachInfo attachInfo, int visibility) {
    //     
    // }

    @Override
    public void bringChildToFront(View child) {
        
    }

    @Override
    boolean dispatchDragEnterExitInPreN(DragEvent event) {
        return false;
    }

    // TODO: Write real docs
    @Override
    public boolean dispatchDragEvent(DragEvent event) {
        return false;
    }

    // Find the frontmost child view that lies under the given point, and calculate
    // the position within its own local coordinate system.
    View findFrontmostDroppableChildAt(float x, float y, PointF outLocalPoint) {
        return null;
    }

    boolean notifyChildOfDragStart(View child) {
        return false;
    }

    @Override
    @Deprecated
    public void dispatchWindowSystemUiVisiblityChanged(int visible) {
        
    }

    @Override
    @Deprecated
    public void dispatchSystemUiVisibilityChanged(int visible) {
        
    }

    @Override
    boolean updateLocalSystemUiVisibility(int localValue, int localChanges) {
        return false;
    }

    @Override
    public boolean dispatchKeyEventPreIme(KeyEvent event) {
        return false;
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        return false;
    }

    @Override
    public boolean dispatchKeyShortcutEvent(KeyEvent event) {
        return false;
    }

    @Override
    public boolean dispatchTrackballEvent(MotionEvent event) {
        return false;
    }

    @Override
    public boolean dispatchCapturedPointerEvent(MotionEvent event) {
        return false;
    }

    @Override
    public void dispatchPointerCaptureChanged(boolean hasCapture) {
        
    }

    @Override
    public PointerIcon onResolvePointerIcon(MotionEvent event, int pointerIndex) {
        return null;
    }

    @SuppressWarnings({"ConstantConditions"})
    @Override
    protected boolean dispatchHoverEvent(MotionEvent event) {
        return false;
    }

    @Override
    boolean dispatchTooltipHoverEvent(MotionEvent event) {
        return false;
    }

    /** @hide */
    @Override
    protected boolean hasHoveredChild() {
        return false;
    }

    /** @hide */
    @Override
    protected boolean pointInHoveredChild(MotionEvent event) {
        return false;
    }

    @Override
    public void addChildrenForAccessibility(ArrayList<View> outChildren) {
        
    }

    public boolean onInterceptHoverEvent(MotionEvent event) {
        return false;
    }

    @Override
    protected boolean dispatchGenericPointerEvent(MotionEvent event) {
        return false;
    }

    @Override
    protected boolean dispatchGenericFocusedEvent(MotionEvent event) {
        return false;
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        return false;
    }

    public ArrayList<View> buildTouchDispatchChildList() {
        return null;
    }

    protected boolean isTransformedTouchPointInView(float x, float y, View child,
            PointF outLocalPoint) {
        return false;
    }

    public void transformPointToViewLocal(float[] point, View child) {
        
    }

    public void setMotionEventSplittingEnabled(boolean split) {
        
    }

    public boolean isMotionEventSplittingEnabled() {
        return false;
    }

    public boolean isTransitionGroup() {
        return false;
    }

    public void setTransitionGroup(boolean isTransitionGroup) {
        
    }

    @Override
    public void requestDisallowInterceptTouchEvent(boolean disallowIntercept) {
        
    }

    public boolean onInterceptTouchEvent(MotionEvent ev) {
        return false;
    }

    @Override
    public boolean requestFocus(int direction, Rect previouslyFocusedRect) {
        return false;
    }

    @SuppressWarnings({"ConstantConditions"})
    protected boolean onRequestFocusInDescendants(int direction,
            Rect previouslyFocusedRect) {
        return false;
    }

    @Override
    public boolean restoreDefaultFocus() {
        return false;
    }

    @TestApi
    @Override
    public boolean restoreFocusInCluster(@FocusRealDirection int direction) {
        return false;
    }

    @Override
    public boolean restoreFocusNotInCluster() {
        return false;
    }

    @Override
    public void dispatchStartTemporaryDetach() {
        
    }

    @Override
    public void dispatchFinishTemporaryDetach() {
        
    }

    // @Override
    // void dispatchAttachedToWindow(AttachInfo info, int visibility) {
    //     
    // }

    @Override
    void dispatchScreenStateChanged(int screenState) {
        
    }

    @Override
    void dispatchMovedToDisplay(Display display, Configuration config) {
        
    }

    /** @hide */
    @Override
    public boolean dispatchPopulateAccessibilityEventInternal(AccessibilityEvent event) {
        return false;
    }

    @Override
    public void dispatchProvideStructure(ViewStructure structure) {
        
    }

    @Override
    public void dispatchProvideAutofillStructure(ViewStructure structure,
            @AutofillFlags int flags) {
        
    }

    /** @hide */
    @Override
    public void dispatchProvideContentCaptureStructure() {
        
    }

    /** @hide */
    @Override
    public void resetSubtreeAutofillIds() {
        
    }

    /** @hide */
    @Override
    public void onInitializeAccessibilityNodeInfoInternal(AccessibilityNodeInfo info) {
        
    }

    @Override
    public void addExtraDataToAccessibilityNodeInfo(@NonNull AccessibilityNodeInfo info,
            @NonNull String extraDataKey, @Nullable Bundle arguments) {
        
    }

    @Override
    public CharSequence getAccessibilityClassName() {
        return null;
    }

    @Override
    public void notifySubtreeAccessibilityStateChanged(View child, View source, int changeType) {
        
    }

    /** @hide */
    @Override
    public void notifySubtreeAccessibilityStateChangedIfNeeded() {
        
    }

    @Override
    void resetSubtreeAccessibilityStateChanged() {
        
    }

    int getNumChildrenForAccessibility() {
        return 0;
    }

    @Override
    public boolean onNestedPrePerformAccessibilityAction(View target, int action, Bundle args) {
        return false;
    }

    @Override
    void calculateAccessibilityDataSensitive() {
        
    }

    @Override
    void dispatchDetachedFromWindow() {
        
    }

    @Override
    protected void internalSetPadding(int left, int top, int right, int bottom) {
        
    }

    @Override
    protected void dispatchSaveInstanceState(SparseArray<Parcelable> container) {
        
    }

    protected void dispatchFreezeSelfOnly(SparseArray<Parcelable> container) {
        
    }

    @Override
    protected void dispatchRestoreInstanceState(SparseArray<Parcelable> container) {
        
    }

    protected void dispatchThawSelfOnly(SparseArray<Parcelable> container) {
        
    }

    @Deprecated
    protected void setChildrenDrawingCacheEnabled(boolean enabled) {
        
    }

    // @Override
    // public Bitmap createSnapshot(ViewDebug.CanvasProvider canvasProvider, boolean skipChildren) {
    //     
    // }

    /** Return true if this ViewGroup is laying out using optical bounds. */
    boolean isLayoutModeOptical() {
        return false;
    }

    @Override
    Insets computeOpticalInsets() {
        return null;
    }

    protected void onDebugDrawMargins(@NonNull Canvas canvas, Paint paint) {
        
    }

    protected void onDebugDraw(@NonNull Canvas canvas) {
        
    }

    @Override
    protected void dispatchDraw(@NonNull Canvas canvas) {
        
    }

    @Override
    public ViewGroupOverlay getOverlay() {
        return null;
    }

    protected int getChildDrawingOrder(int childCount, int drawingPosition) {
        return 0;
    }

    public final int getChildDrawingOrder(int drawingPosition) {
        return 0;
    }

    ArrayList<View> buildOrderedChildList() {
        return null;
    }

    @Override
    protected void dispatchGetDisplayList() {
        
    }

    protected boolean drawChild(@NonNull Canvas canvas, View child, long drawingTime) {
        return false;
    }

    @Override
    void getScrollIndicatorBounds(@NonNull Rect out) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean getClipChildren() {
        return false;
    }

    public void setClipChildren(boolean clipChildren) {
        
    }

    public void setClipToPadding(boolean clipToPadding) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    public boolean getClipToPadding() {
        return false;
    }

    @Override
    public void dispatchSetSelected(boolean selected) {
        
    }

    @Override
    public void dispatchSetActivated(boolean activated) {
        
    }

    @Override
    protected void dispatchSetPressed(boolean pressed) {
        
    }

    @Override
    public void dispatchDrawableHotspotChanged(float x, float y) {
        
    }

    @Override
    void dispatchCancelPendingInputEvents() {
        
    }

    protected void setStaticTransformationsEnabled(boolean enabled) {
        
    }

    protected boolean getChildStaticTransformation(View child, Transformation t) {
        return false;
    }

    Transformation getChildTransformation() {
        return null;
    }

    @Override
    protected <T extends View> T findViewTraversal(@IdRes int id) {
        return null;
    }

    @Override
    protected <T extends View> T findViewWithTagTraversal(Object tag) {
        return null;
    }

    @Override
    protected <T extends View> T findViewByPredicateTraversal(Predicate<View> predicate,
            View childToSkip) {
        return null;
    }

    public void addTransientView(View view, int index) {
        
    }

    public void removeTransientView(View view) {
        
    }

    public int getTransientViewCount() {
        return 0;
    }

    public int getTransientViewIndex(int position) {
        return 0;
    }

    public View getTransientView(int position) {
        return null;
    }

    public void addView(View child) {
        
    }

    public void addView(View child, int index) {
        
    }

    public void addView(View child, int width, int height) {
        
    }

    @Override
    public void addView(View child, LayoutParams params) {
        
    }

    public void addView(View child, int index, LayoutParams params) {
        
    }

    @Override
    public void updateViewLayout(View view, LayoutParams params) {
        
    }

    protected boolean checkLayoutParams(LayoutParams p) {
        return false;
    }

    public interface OnHierarchyChangeListener {
        void onChildViewAdded(View parent, View child);

        void onChildViewRemoved(View parent, View child);
    }

    public void setOnHierarchyChangeListener(OnHierarchyChangeListener listener) {
        
    }

    void dispatchViewAdded(View child) {
        
    }

    public void onViewAdded(View child) {
    }

    void dispatchViewRemoved(View child) {
        
    }

    public void onViewRemoved(View child) {
    }

    @Override
    protected void onAttachedToWindow() {
        
    }

    @Override
    protected void onDetachedFromWindow() {
        
    }

    /** @hide */
    @Override
    protected void destroyHardwareResources() {
        
    }

    protected boolean addViewInLayout(View child, int index, LayoutParams params) {
        return false;
    }

    protected boolean addViewInLayout(View child, int index, LayoutParams params,
            boolean preventRequestLayout) {
        return false;
    }

    protected void cleanupLayoutState(View child) {
        
    }

    protected void attachLayoutAnimationParameters(View child,
            LayoutParams params, int index, int count) {
        
    }

    @Override
    public void removeView(View view) {
        
    }

    public void removeViewInLayout(View view) {
        
    }

    public void removeViewsInLayout(int start, int count) {
        
    }

    public void removeViewAt(int index) {
        
    }

    public void removeViews(int start, int count) {
        
    }

    public void setLayoutTransition(LayoutTransition transition) {
        
    }

    public LayoutTransition getLayoutTransition() {
        return null;
    }

    public void removeAllViews() {
        
    }

    public void removeAllViewsInLayout() {
        
    }

    protected void removeDetachedView(View child, boolean animate) {
        
    }

    protected void attachViewToParent(View child, int index, LayoutParams params) {
        
    }

    protected void detachViewFromParent(View child) {
        
    }

    protected void detachViewFromParent(int index) {
        
    }

    protected void detachViewsFromParent(int start, int count) {
        
    }

    protected void detachAllViewsFromParent() {
        
    }

    @Override
    @CallSuper
    public void onDescendantInvalidated(@NonNull View child, @NonNull View target) {
        
    }


    @Deprecated
    @Override
    public final void invalidateChild(View child, final Rect dirty) {
        
    }

    @Deprecated
    @Override
    public ViewParent invalidateChildInParent(final int[] location, final Rect dirty) {
        return null;
    }

    public final void offsetDescendantRectToMyCoords(View descendant, Rect rect) {
        
    }

    public final void offsetRectIntoDescendantCoords(View descendant, Rect rect) {
        
    }

    void offsetRectBetweenParentAndChild(View descendant, Rect rect,
            boolean offsetFromChildToParent, boolean clipToBounds) {
        
    }

    public void offsetChildrenTopAndBottom(int offset) {
        
    }

    @Override
    public boolean getChildVisibleRect(View child, Rect r, android.graphics.Point offset) {
        return false;
    }

    public boolean getChildVisibleRect(
            View child, Rect r, android.graphics.Point offset, boolean forceParentCheck) {
        return false;
    }

    @Override
    public final void layout(int l, int t, int r, int b) {
        
    }

    @Override
    protected abstract void onLayout(boolean changed,
            int l, int t, int r, int b);

    protected boolean canAnimate() {
        return false;
    }

    public void startLayoutAnimation() {
        
    }

    public void scheduleLayoutAnimation() {
        
    }

    public void setLayoutAnimation(LayoutAnimationController controller) {
        
    }

    public LayoutAnimationController getLayoutAnimation() {
        return null;
    }

    @Deprecated
    public boolean isAnimationCacheEnabled() {
        return false;
    }

    @Deprecated
    public void setAnimationCacheEnabled(boolean enabled) {
        
    }

    @Deprecated
    public boolean isAlwaysDrawnWithCacheEnabled() {
        return false;
    }

    @Deprecated
    public void setAlwaysDrawnWithCacheEnabled(boolean always) {
        
    }

    @Deprecated
    protected boolean isChildrenDrawnWithCacheEnabled() {
        return false;
    }

    @Deprecated
    protected void setChildrenDrawnWithCacheEnabled(boolean enabled) {
        
    }

    @ViewDebug.ExportedProperty(category = "drawing")
    protected boolean isChildrenDrawingOrderEnabled() {
        return false;
    }

    protected void setChildrenDrawingOrderEnabled(boolean enabled) {
        
    }

    @Deprecated
    @ViewDebug.ExportedProperty(category = "drawing", mapping = {
        @ViewDebug.IntToString(from = PERSISTENT_NO_CACHE,        to = "NONE"),
        @ViewDebug.IntToString(from = PERSISTENT_ANIMATION_CACHE, to = "ANIMATION"),
        @ViewDebug.IntToString(from = PERSISTENT_SCROLLING_CACHE, to = "SCROLLING"),
        @ViewDebug.IntToString(from = PERSISTENT_ALL_CACHES,      to = "ALL")
    })
    public int getPersistentDrawingCache() {
        return 0;
    }

    @Deprecated
    public void setPersistentDrawingCache(int drawingCacheToKeep) {
        
    }

    // @Override
    void invalidateInheritedLayoutMode(int layoutModeOfRoot) {
        
    }

    public int getLayoutMode() {
        return 0;
    }

    public void setLayoutMode(int layoutMode) {
        
    }

    public LayoutParams generateLayoutParams(AttributeSet attrs) {
        return null;
    }

    protected LayoutParams generateLayoutParams(LayoutParams p) {
        return null;
    }

    protected LayoutParams generateDefaultLayoutParams() {
        return null;
    }

    @Override
    protected void debug(int depth) {
        
    }

    public int indexOfChild(View child) {
        return 0;
    }

    public int getChildCount() {
        return 0;
    }

    public View getChildAt(int index) {
        return null;
    }

    protected void measureChildren(int widthMeasureSpec, int heightMeasureSpec) {
        
    }

    protected void measureChild(View child, int parentWidthMeasureSpec,
            int parentHeightMeasureSpec) {
        
    }

    protected void measureChildWithMargins(View child,
            int parentWidthMeasureSpec, int widthUsed,
            int parentHeightMeasureSpec, int heightUsed) {
        
    }

    public static int getChildMeasureSpec(int spec, int padding, int childDimension) {
        return 0;
    }


    public void clearDisappearingChildren() {
        
    }

    void finishAnimatingView(final View view, Animation animation) {
        
    }

    boolean isViewTransitioning(View view) {
        return false;
    }

    public void startViewTransition(View view) {
        
    }

    public void endViewTransition(View view) {
        
    }

    public void suppressLayout(boolean suppress) {
        
    }

    public boolean isLayoutSuppressed() {
        return false;
    }

    @Override
    public boolean gatherTransparentRegion(Region region) {
        return false;
    }

    @Override
    public void requestTransparentRegion(View child) {
        
    }

    // @Override
    public void subtractObscuredTouchableRegion(Region touchableRegion, View view) {
        
    }

    // @Override
    public boolean getChildLocalHitRegion(@NonNull View child, @NonNull Region region,
            @NonNull Matrix matrix, boolean isHover) {
        return false;
    }

    @Override
    public WindowInsets dispatchApplyWindowInsets(WindowInsets insets) {
        return null;
    }

    @Override
    public void setWindowInsetsAnimationCallback(
            @Nullable WindowInsetsAnimation.Callback callback) {
        
    }

    @Override
    public boolean hasWindowInsetsAnimationCallback() {
        return false;
    }

    @Override
    public void dispatchWindowInsetsAnimationPrepare(
            @NonNull WindowInsetsAnimation animation) {
        
    }

    @Override
    @NonNull
    public Bounds dispatchWindowInsetsAnimationStart(
            @NonNull WindowInsetsAnimation animation, @NonNull Bounds bounds) {
        return null;
    }

    @Override
    @NonNull
    public WindowInsets dispatchWindowInsetsAnimationProgress(@NonNull WindowInsets insets,
            @NonNull List<WindowInsetsAnimation> runningAnimations) {
        return null;
    }

    @Override
    public void dispatchWindowInsetsAnimationEnd(@NonNull WindowInsetsAnimation animation) {
        
    }

    // @Override
    // public void dispatchScrollCaptureSearch(
    //         @NonNull Rect localVisibleRect, @NonNull Point windowOffset,
    //         @NonNull Consumer<ScrollCaptureTarget> targets) {
    //     
    // }

    public Animation.AnimationListener getLayoutAnimationListener() {
        return null;
    }

    @Override
    protected void drawableStateChanged() {
        
    }

    @Override
    public void jumpDrawablesToCurrentState() {
        
    }

    @Override
    protected int[] onCreateDrawableState(int extraSpace) {
        return null;
    }

    public void setAddStatesFromChildren(boolean addsStates) {
        
    }

    public boolean addStatesFromChildren() {
        return false;
    }

    @Override
    public void childDrawableStateChanged(View child) {
        
    }

    public void setLayoutAnimationListener(Animation.AnimationListener animationListener) {
        
    }

    public void requestTransitionStart(LayoutTransition transition) {
        
    }

    @Override
    public boolean resolveRtlPropertiesIfNeeded() {
        return false;
    }

    @Override
    public boolean resolveLayoutDirection() {
        return false;
    }

    @Override
    public boolean resolveTextDirection() {
        return false;
    }

    @Override
    public boolean resolveTextAlignment() {
        return false;
    }

    @Override
    public void resolvePadding() {
        
    }

    @Override
    protected void resolveDrawables() {
        
    }

    @Override
    public void resolveLayoutParams() {
        
    }

    @TestApi
    @Override
    public void resetResolvedLayoutDirection() {
        
    }

    @TestApi
    @Override
    public void resetResolvedTextDirection() {
        
    }

    @TestApi
    @Override
    public void resetResolvedTextAlignment() {
        
    }

    @TestApi
    @Override
    public void resetResolvedPadding() {
        
    }

    @TestApi
    @Override
    protected void resetResolvedDrawables() {
        
    }

    public boolean shouldDelayChildPressedState() {
        return true;
    }

    @Override
    public boolean onStartNestedScroll(View child, View target, int nestedScrollAxes) {
        return false;
    }

    @Override
    public void onNestedScrollAccepted(View child, View target, int axes) {
        
    }

    @Override
    public void onStopNestedScroll(View child) {
        
    }

    @Override
    public void onNestedScroll(View target, int dxConsumed, int dyConsumed,
            int dxUnconsumed, int dyUnconsumed) {
        
    }

    @Override
    public void onNestedPreScroll(View target, int dx, int dy, int[] consumed) {
        
    }

    @Override
    public boolean onNestedFling(View target, float velocityX, float velocityY, boolean consumed) {
        return false;
    }

    @Override
    public boolean onNestedPreFling(View target, float velocityX, float velocityY) {
        return false;
    }

    public int getNestedScrollAxes() {
        return 0;
    }

    /** @hide */
    protected void onSetLayoutParams(View child, LayoutParams layoutParams) {
        
    }

    /** @hide */
    @Override
    public void captureTransitioningViews(List<View> transitioningViews) {
        
    }

    /** @hide */
    @Override
    public void findNamedViews(Map<String, View> namedElements) {
        
    }

    @Override
    boolean hasUnhandledKeyListener() {
        return false;
    }

    void incrementChildUnhandledKeyListeners() {
        
    }

    void decrementChildUnhandledKeyListeners() {
        
    }

    @Override
    View dispatchUnhandledKeyEvent(KeyEvent evt) {
        return null;
    }

    public static class LayoutParams {
        @SuppressWarnings({"UnusedDeclaration"})
        @Deprecated
        public static final int FILL_PARENT = -1;

        public static final int MATCH_PARENT = -1;

        public static final int WRAP_CONTENT = -2;

        public int width;

        public int height;

        public LayoutAnimationController.AnimationParameters layoutAnimationParameters;

        public LayoutParams(Context c, AttributeSet attrs) {
            
        }

        public LayoutParams(int width, int height) {
            this.width = width;
            this.height = height;
        }

        public LayoutParams(LayoutParams source) {
            this.width = source.width;
            this.height = source.height;
        }

        LayoutParams() {
        }

        protected void setBaseAttributes(TypedArray a, int widthAttr, int heightAttr) {
            
        }

        public void resolveLayoutDirection(int layoutDirection) {
        }

        public String debug(String output) {
            return output + "ViewGroup.LayoutParams={ width="
                    + sizeToString(width) + ", height=" + sizeToString(height) + " }";
        }

        public void onDebugDraw(View view, Canvas canvas, Paint paint) {
        }

        protected static String sizeToString(int size) {
            if (size == WRAP_CONTENT) {
                return "wrap-content";
            }
            if (size == MATCH_PARENT) {
                return "match-parent";
            }
            return String.valueOf(size);
        }

        // /** @hide */
        // void encode(@NonNull ViewHierarchyEncoder encoder) {
        //     
        // }

        // /** @hide */
        // protected void encodeProperties(@NonNull ViewHierarchyEncoder encoder) {
        //     
        // }
    }

    public static class MarginLayoutParams extends LayoutParams {
        @ViewDebug.ExportedProperty(category = "layout")
        public int leftMargin;

        @ViewDebug.ExportedProperty(category = "layout")
        public int topMargin;

        @ViewDebug.ExportedProperty(category = "layout")
        public int rightMargin;

        @ViewDebug.ExportedProperty(category = "layout")
        public int bottomMargin;

        byte mMarginFlags;

        public MarginLayoutParams(Context c, AttributeSet attrs) {
            
        }

        public MarginLayoutParams(int width, int height) {
            super(width, height);
            
        }

        public MarginLayoutParams(MarginLayoutParams source) {
            
        }

        public MarginLayoutParams(LayoutParams source) {
            super(source);
            
        }

        public final void copyMarginsFrom(MarginLayoutParams source) {
            
        }

        public void setMargins(int left, int top, int right, int bottom) {
            
        }

        public void setMarginsRelative(int start, int top, int end, int bottom) {
            
        }

        public void setMarginStart(int start) {
            
        }

        public int getMarginStart() {
            return 0;
        }

        public void setMarginEnd(int end) {
            
        }

        public int getMarginEnd() {
            return 0;
        }

        public boolean isMarginRelative() {
            return false;
        }

        public void setLayoutDirection(int layoutDirection) {
            
        }

        public int getLayoutDirection() {
            return 0;
        }

        @Override
        public void resolveLayoutDirection(int layoutDirection) {
            
        }

        public boolean isLayoutRtl() {
            return false;
        }

        @Override
        public void onDebugDraw(View view, Canvas canvas, Paint paint) {
            
        }

        // /** @hide */
        // @Override
        // protected void encodeProperties(@NonNull ViewHierarchyEncoder encoder) {
        //     
        // }
    }

    static class ChildListForAccessibility {

        public static ChildListForAccessibility obtain(ViewGroup parent, boolean sort) {
            return null;
        }

        public void recycle() {
            
        }

        public int getChildCount() {
            return 0;
        }

        public View getChildAt(int index) {
            return null;
        }
    }

    static class ViewLocationHolder implements Comparable<ViewLocationHolder> {

        public static final int COMPARISON_STRATEGY_STRIPE = 1;

        public static final int COMPARISON_STRATEGY_LOCATION = 2;

        public View mView;

        public static ViewLocationHolder obtain(ViewGroup root, View view) {
            return null;
        }

        public static void setComparisonStrategy(int strategy) {
            
        }

        public void recycle() {
            
        }

        @Override
        public int compareTo(ViewLocationHolder another) {
            return 0;
        }
    }

    // /** @hide */
    // @Override
    // protected void encodeProperties(@NonNull ViewHierarchyEncoder encoder) {
    //     
    // }

    /** @hide */
    // @Override
    public final void onDescendantUnbufferedRequested() {
        
    }

    // @Override
    // public void dispatchCreateViewTranslationRequest(@NonNull Map<AutofillId, long[]> viewIds,
    //         @NonNull int[] supportedFormats,
    //         @Nullable TranslationCapability capability,
    //         @NonNull List<ViewTranslationRequest> requests) {
    //     
    // }

    // @Nullable
    // @Override
    // public OnBackInvokedDispatcher findOnBackInvokedDispatcherForChild(@NonNull View child,
    //         @NonNull View requester) {
    //     
    // }

    @Override
    public void setRequestedFrameRate(float frameRate) {
        
    }

    public void propagateRequestedFrameRate(float frameRate, boolean forceOverride) {
        
    }

    @Override
    void overrideFrameRate(float frameRate, boolean forceOverride) {
        
    }
}
