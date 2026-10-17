package androidx.fragment.app;

import android.view.Window;

import androidx.appcompat.app.AppCompatActivity;

/*
 * Desktop stand-in for the AndroidX class of the same name. Extensions build
 * their settings and Cloudflare dialogs on it; there is no window system here,
 * so showing one does nothing and lifecycle callbacks never fire.
 */
public class FragmentActivity extends AppCompatActivity {
    public void runOnUiThread(Runnable action) { action.run(); }

    public Window getWindow() { return null; }

    public boolean isFinishing() { return false; }

    public boolean isDestroyed() { return false; }
}
