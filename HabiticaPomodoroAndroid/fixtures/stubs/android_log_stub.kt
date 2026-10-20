// Harness stub: android.util.Log — echoes to stderr so failure logs stay visible.
package android.util

object Log {
    @JvmStatic fun e(tag: String, msg: String): Int { System.err.println("[E/$tag] $msg"); return 0 }
    @JvmStatic fun e(tag: String, msg: String, tr: Throwable?): Int { System.err.println("[E/$tag] $msg $tr"); return 0 }
    @JvmStatic fun w(tag: String, msg: String): Int { System.err.println("[W/$tag] $msg"); return 0 }
    @JvmStatic fun i(tag: String, msg: String): Int { System.err.println("[I/$tag] $msg"); return 0 }
    @JvmStatic fun d(tag: String, msg: String): Int { System.err.println("[D/$tag] $msg"); return 0 }
    @JvmStatic fun v(tag: String, msg: String): Int { System.err.println("[V/$tag] $msg"); return 0 }
}
