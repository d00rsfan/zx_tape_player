package io.github.d00rsfan.zx_tape_player

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (rather than the default FlutterActivity) is used
// because androidx.activity's enableEdgeToEdge extension is defined on
// ComponentActivity, and only FlutterFragmentActivity sits in that
// inheritance chain (FlutterFragmentActivity → FragmentActivity →
// ComponentActivity). Plain FlutterActivity extends android.app.Activity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Forces edge-to-edge on Android <15 to match the default behaviour
        // on Android 15+, and routes the status/nav-bar configuration
        // through the modern WindowInsetsController APIs instead of the
        // Window.setNavigationBarColor() / setStatusBarColor() calls that
        // were deprecated in API 35.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
