// Harness stub: androidx.lifecycle.AndroidViewModel + viewModelScope.
// The real viewModelScope dispatches on Main.immediate; here it is Unconfined so
// coroutine bodies run synchronously on the calling thread until a real
// suspension (delay). The substitute HabiticaAPI never suspends, which makes
// every VM flow deterministic inside a case.
package androidx.lifecycle

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

abstract class ViewModel

abstract class AndroidViewModel(private val application: Application) : ViewModel() {
    val harnessScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    @Suppress("UNCHECKED_CAST")
    fun <T : Application> getApplication(): T = application as T
}

val ViewModel.viewModelScope: CoroutineScope
    get() = (this as AndroidViewModel).harnessScope
