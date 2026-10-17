package android.graphics;

import android.os.Parcel;
import android.os.Parcelable;

public class RectF implements Parcelable {
    public float left;
    public float top;
    public float right;
    public float bottom;

    public RectF() {
    }

    public RectF(float left, float top, float right, float bottom) {
        set(left, top, right, bottom);
    }

    public RectF(RectF r) {
        if (r != null) set(r);
    }

    public RectF(Rect r) {
        if (r != null) set(r);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof RectF)) return false;
        RectF r = (RectF) o;
        return left == r.left && top == r.top && right == r.right && bottom == r.bottom;
    }

    @Override
    public int hashCode() {
        int result = Float.floatToIntBits(left);
        result = 31 * result + Float.floatToIntBits(top);
        result = 31 * result + Float.floatToIntBits(right);
        return 31 * result + Float.floatToIntBits(bottom);
    }

    @Override
    public String toString() {
        return "RectF(" + left + ", " + top + ", " + right + ", " + bottom + ")";
    }

    public String toShortString() {
        return "[" + left + "," + top + "][" + right + "," + bottom + "]";
    }

    public final boolean isEmpty() {
        return left >= right || top >= bottom;
    }

    public final float width() {
        return right - left;
    }

    public final float height() {
        return bottom - top;
    }

    public final float centerX() {
        return (left + right) * 0.5f;
    }

    public final float centerY() {
        return (top + bottom) * 0.5f;
    }

    public void setEmpty() {
        left = right = top = bottom = 0;
    }

    public void set(float left, float top, float right, float bottom) {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }

    public void set(RectF src) {
        set(src.left, src.top, src.right, src.bottom);
    }

    public void set(Rect src) {
        set(src.left, src.top, src.right, src.bottom);
    }

    public void offset(float dx, float dy) {
        left += dx;
        top += dy;
        right += dx;
        bottom += dy;
    }

    public void offsetTo(float newLeft, float newTop) {
        right += newLeft - left;
        bottom += newTop - top;
        left = newLeft;
        top = newTop;
    }

    public void inset(float dx, float dy) {
        left += dx;
        top += dy;
        right -= dx;
        bottom -= dy;
    }

    public boolean contains(float x, float y) {
        return left < right && top < bottom && x >= left && x < right && y >= top && y < bottom;
    }

    public boolean contains(float left, float top, float right, float bottom) {
        return this.left < this.right && this.top < this.bottom
                && this.left <= left && this.top <= top && this.right >= right && this.bottom >= bottom;
    }

    public boolean contains(RectF r) {
        return contains(r.left, r.top, r.right, r.bottom);
    }

    public boolean intersect(float left, float top, float right, float bottom) {
        if (this.left < right && left < this.right && this.top < bottom && top < this.bottom) {
            if (this.left < left) this.left = left;
            if (this.top < top) this.top = top;
            if (this.right > right) this.right = right;
            if (this.bottom > bottom) this.bottom = bottom;
            return true;
        }
        return false;
    }

    public boolean intersect(RectF r) {
        return intersect(r.left, r.top, r.right, r.bottom);
    }

    public boolean setIntersect(RectF a, RectF b) {
        if (a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom) {
            set(Math.max(a.left, b.left), Math.max(a.top, b.top), Math.min(a.right, b.right), Math.min(a.bottom, b.bottom));
            return true;
        }
        return false;
    }

    public boolean intersects(float left, float top, float right, float bottom) {
        return this.left < right && left < this.right && this.top < bottom && top < this.bottom;
    }

    public static boolean intersects(RectF a, RectF b) {
        return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
    }

    public void round(Rect dst) {
        dst.set(Math.round(left), Math.round(top), Math.round(right), Math.round(bottom));
    }

    public void roundOut(Rect dst) {
        dst.set((int) Math.floor(left), (int) Math.floor(top), (int) Math.ceil(right), (int) Math.ceil(bottom));
    }

    public void union(float left, float top, float right, float bottom) {
        if (left >= right || top >= bottom) return;
        if (this.left < this.right && this.top < this.bottom) {
            if (this.left > left) this.left = left;
            if (this.top > top) this.top = top;
            if (this.right < right) this.right = right;
            if (this.bottom < bottom) this.bottom = bottom;
        } else {
            set(left, top, right, bottom);
        }
    }

    public void union(RectF r) {
        union(r.left, r.top, r.right, r.bottom);
    }

    public void union(float x, float y) {
        if (x < left) left = x;
        else if (x > right) right = x;
        if (y < top) top = y;
        else if (y > bottom) bottom = y;
    }

    public void sort() {
        if (left > right) {
            float t = left;
            left = right;
            right = t;
        }
        if (top > bottom) {
            float t = top;
            top = bottom;
            bottom = t;
        }
    }

    @Override
    public int describeContents() {
        return 0;
    }

    @Override
    public void writeToParcel(Parcel out, int flags) {
        out.writeFloat(left);
        out.writeFloat(top);
        out.writeFloat(right);
        out.writeFloat(bottom);
    }

    public void readFromParcel(Parcel in) {
        left = in.readFloat();
        top = in.readFloat();
        right = in.readFloat();
        bottom = in.readFloat();
    }

    public static final Parcelable.Creator<RectF> CREATOR = new Parcelable.Creator<RectF>() {
        @Override
        public RectF createFromParcel(Parcel in) {
            RectF r = new RectF();
            r.readFromParcel(in);
            return r;
        }

        @Override
        public RectF[] newArray(int size) {
            return new RectF[size];
        }
    };
}
