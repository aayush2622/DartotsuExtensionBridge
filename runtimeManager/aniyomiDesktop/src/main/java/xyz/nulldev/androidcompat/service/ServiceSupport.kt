package xyz.nulldev.androidcompat.service

import android.app.Service
import android.content.Context
import android.content.Intent
import com.aayush262.dartotsu_extension_bridge.LogLevel
import com.aayush262.dartotsu_extension_bridge.Logger
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Service emulation class
 *
 * TODO Possibly handle starting services via bindService
 */

class ServiceSupport {
    val runningServices = ConcurrentHashMap<String, Service>()


    fun startService(
        @Suppress("UNUSED_PARAMETER") context: Context,
        intent: Intent,
    ) {
        val name = intentToClassName(intent)

        Logger.log("Starting service: $name", LogLevel.DEBUG)

        val service = serviceInstanceFromClass(name)

        runningServices[name] = service

        // Setup service
        thread {
            callOnCreate(service)
            // TODO Handle more complex cases
            service.onStartCommand(intent, 0, 0)
        }
    }

    fun stopService(
        @Suppress("UNUSED_PARAMETER") context: Context,
        intent: Intent,
    ) {
        val name = intentToClassName(intent)
        stopService(name)
    }

    fun stopService(name: String) {
        Logger.log("Stopping service: $name", LogLevel.DEBUG)
        val service = runningServices.remove(name)
        if (service == null) {
            Logger.log("Service $name is not running!", LogLevel.WARNING)
        } else {
            thread {
                service.onDestroy()
            }
        }
    }

    fun stopSelf(service: Service) {
        stopService(service.javaClass.name)
    }

    fun callOnCreate(service: Service) = service.onCreate()

    fun intentToClassName(intent: Intent) = intent.component.className!!

    fun serviceInstanceFromClass(className: String): Service {
        val clazzObj = Class.forName(className)
        return clazzObj.getDeclaredConstructor().newInstance() as? Service
            ?: throw IllegalArgumentException("$className is not a Service!")
    }
}
