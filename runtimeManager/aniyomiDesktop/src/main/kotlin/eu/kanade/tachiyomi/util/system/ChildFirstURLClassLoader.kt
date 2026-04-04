package eu.kanade.tachiyomi.util.system

import java.io.IOException
import java.net.URL
import java.net.URLClassLoader
import java.util.Enumeration

class ChildFirstURLClassLoader(urls: Array<URL?>) : URLClassLoader(urls) {
    @Throws(ClassNotFoundException::class)
    public override fun loadClass(name: String, resolve: Boolean): Class<*>? {
        synchronized(getClassLoadingLock(name)) {
            var c = findLoadedClass(name)

            if (c == null) {
                for (alwaysParentFirstPattern in alwaysParentFirstPatterns) {
                    if (name.startsWith(alwaysParentFirstPattern!!)) {
                        return super.loadClass(name, resolve)
                    }
                }
                try {
                    c = findClass(name)
                    if (resolve) {
                        resolveClass(c)
                    }
                } catch (_: ClassNotFoundException) {
                    c = super.loadClass(name, resolve)
                }
            } else if (resolve) {
                resolveClass(c)
            }
            return c
        }
    }

    override fun getResource(name: String?): URL? {
        val urlClassLoaderResource = findResource(name)

        if (urlClassLoaderResource != null) {
            return urlClassLoaderResource
        }

        return super.getResource(name)
    }

    @Throws(IOException::class)
    override fun getResources(name: String?): Enumeration<URL?> {
        val urlClassLoaderResources = findResources(name)

        val result: MutableList<URL?> = ArrayList()

        while (urlClassLoaderResources.hasMoreElements()) {
            result.add(urlClassLoaderResources.nextElement())
        }

        val parentResources = parent.getResources(name)

        while (parentResources.hasMoreElements()) {
            result.add(parentResources.nextElement())
        }

        return object : Enumeration<URL?> {
            val iter: MutableIterator<URL?> = result.iterator()

            override fun hasMoreElements(): Boolean {
                return iter.hasNext()
            }

            override fun nextElement(): URL? {
                return iter.next()
            }
        }
    }

    companion object {
        /**
         * The classes that should always go through the parent ClassLoader.
         */
        private val alwaysParentFirstPatterns = arrayOf<String?>(
            "java.", "javax.", "sun.", "com.sun.", "jdk.internal.", "org.xml.", "org.w3c.",
            "okhttp3."
        )

        init {
            registerAsParallelCapable()
        }
    }
}