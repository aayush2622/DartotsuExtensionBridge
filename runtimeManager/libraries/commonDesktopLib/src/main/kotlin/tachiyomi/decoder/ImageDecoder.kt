package tachiyomi.decoder

import android.graphics.Bitmap
import android.graphics.Rect
import java.awt.image.BufferedImage
import java.io.InputStream
import javax.imageio.ImageIO

class ImageDecoder private constructor(private var image: BufferedImage?) {

    val width: Int get() = image?.width ?: 0

    val height: Int get() = image?.height ?: 0

    fun decode(region: Rect = Rect(0, 0, width, height), sampleSize: Int = 1): Bitmap? {
        val source = image ?: return null
        val left = region.left.coerceIn(0, source.width)
        val top = region.top.coerceIn(0, source.height)
        val w = (region.right.coerceIn(0, source.width) - left)
        val h = (region.bottom.coerceIn(0, source.height) - top)
        if (w <= 0 || h <= 0) return null
        val step = sampleSize.coerceAtLeast(1)
        val out = BufferedImage((w + step - 1) / step, (h + step - 1) / step, BufferedImage.TYPE_INT_ARGB)
        val g = out.createGraphics()
        g.drawImage(source, 0, 0, out.width, out.height, left, top, left + w, top + h, null)
        g.dispose()
        return Bitmap(out)
    }

    fun recycle() {
        image = null
    }

    companion object {
        @JvmStatic
        fun newInstance(stream: InputStream, cropBorders: Boolean = false, displayProfile: ByteArray? = null): ImageDecoder? =
            runCatching { ImageIO.read(stream) }.getOrNull()?.let(::ImageDecoder)
    }
}
