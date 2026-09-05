package io.github.d00rsfan.zx_tape_player

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter configures the window in super.onCreate(), so applying this
        // before super would let the embedding overwrite our system bar setup.
        configureEdgeToEdge()
    }

    override fun onPostResume() {
        super.onPostResume()
        // Flutter restores its own system UI here. In particular, its Dart
        // edgeToEdge mode is a no-op on API 24-28, which we still support.
        configureEdgeToEdge()
    }

    private fun configureEdgeToEdge() {
        WindowCompat.enableEdgeToEdge(window)
        // Every screen uses a dark background, regardless of the device theme.
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        // Insets must reach Flutter unchanged; SafeArea handles content padding.
    }
}
