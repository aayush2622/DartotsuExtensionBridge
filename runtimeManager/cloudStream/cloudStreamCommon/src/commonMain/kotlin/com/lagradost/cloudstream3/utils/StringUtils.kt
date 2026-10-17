package com.lagradost.cloudstream3.utils

import java.net.URLDecoder
import java.net.URLEncoder

fun String.encodeUri(): String {
    return URLEncoder.encode(this, "UTF-8")
}

fun String.decodeUri(): String {
    return URLDecoder.decode(this, "UTF-8")
}

object StringUtils {
    fun String.decodeUrl(): String = URLDecoder.decode(this, "UTF-8")

    fun String.encodeUrl(): String = URLEncoder.encode(this, "UTF-8")

    fun String.encodeUri(): String = encodeUrl()

    fun String.decodeUri(): String = decodeUrl()
}
