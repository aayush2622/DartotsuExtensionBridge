package ca.mpreg.imagedecoder

import java.awt.image.BufferedImage
import java.io.InputStream
import java.nio.ByteBuffer
import javax.imageio.ImageIO

class ImageDecoder private constructor(private var image: BufferedImage?) : AutoCloseable {

    class Frame(val width: Int, val height: Int, val image: ByteBuffer)

    val isHdr: Boolean get() = false

    fun decodeNext(): Frame? {
        val source = image ?: return null
        image = null
        val buffer = ByteBuffer.allocateDirect(source.width * source.height * 4)
        for (y in 0 until source.height) {
            for (x in 0 until source.width) {
                val argb = source.getRGB(x, y)
                buffer.put((argb shr 16).toByte())
                buffer.put((argb shr 8).toByte())
                buffer.put(argb.toByte())
                buffer.put((argb ushr 24).toByte())
            }
        }
        buffer.rewind()
        return Frame(source.width, source.height, buffer)
    }

    override fun close() {
        image = null
    }

    companion object {
        @JvmStatic
        fun open(stream: InputStream, hdr: Boolean = false): ImageDecoder? =
            runCatching { ImageIO.read(stream) }.getOrNull()?.let(::ImageDecoder)
    }
}
