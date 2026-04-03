package eu.kanade.tachiyomi.util.system

import java.io.IOException
import java.io.InputStream
import java.lang.ClassLoader.getSystemClassLoader
import java.net.URL
import java.net.URLClassLoader
import java.util.Enumeration

class ChildFirstURLClassLoader(
    urls: Array<URL>,
    parent: ClassLoader? = null,
) : URLClassLoader(urls, parent) {
    private val systemClassLoader: ClassLoader? = getSystemClassLoader()

    override fun loadClass(name: String?, resolve: Boolean): Class<*> {

        val c = findLoadedClass(name)

        if (c != null) {
            return c
        }

        if (systemClassLoader != null) {
            try {
                val sys = systemClassLoader.loadClass(name)

                return sys
            } catch (_: ClassNotFoundException) {
            }
        }

        try {
            val local = findClass(name)
            return local
        } catch (_: ClassNotFoundException) {
        }

        try {
            val parentLoaded = super.loadClass(name, resolve)
            return parentLoaded
        } catch (e: ClassNotFoundException) {
            throw e
        }
    }

    override fun getResource(name: String?): URL? =
        systemClassLoader?.getResource(name)
            ?: findResource(name)
            ?: super.getResource(name)

    override fun getResources(name: String?): Enumeration<URL> {
        val systemUrls = systemClassLoader?.getResources(name)
        val localUrls = findResources(name)
        val parentUrls = parent?.getResources(name)
        val urls =
            buildList {
                while (systemUrls?.hasMoreElements() == true) {
                    add(systemUrls.nextElement())
                }

                while (localUrls?.hasMoreElements() == true) {
                    add(localUrls.nextElement())
                }

                while (parentUrls?.hasMoreElements() == true) {
                    add(parentUrls.nextElement())
                }
            }

        return object : Enumeration<URL> {
            val iterator = urls.iterator()

            override fun hasMoreElements() = iterator.hasNext()

            override fun nextElement() = iterator.next()
        }
    }

    override fun getResourceAsStream(name: String?): InputStream? {
        return try {
            getResource(name)?.openStream()
        } catch (_: IOException) {
            return null
        }
    }
}