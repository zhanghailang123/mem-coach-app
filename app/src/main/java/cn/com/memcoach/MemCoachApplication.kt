package cn.com.memcoach

import android.app.Application

class MemCoachApplication : Application() {
    companion object {
        lateinit var instance: MemCoachApplication
            private set
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }
}
