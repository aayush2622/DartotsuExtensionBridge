package android.media;

import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import java.io.FileDescriptor;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public class MediaMetadataRetriever implements AutoCloseable {
    public static final int METADATA_KEY_CD_TRACK_NUMBER = 0;
    public static final int METADATA_KEY_ALBUM = 1;
    public static final int METADATA_KEY_ARTIST = 2;
    public static final int METADATA_KEY_AUTHOR = 3;
    public static final int METADATA_KEY_COMPOSER = 4;
    public static final int METADATA_KEY_DATE = 5;
    public static final int METADATA_KEY_GENRE = 6;
    public static final int METADATA_KEY_TITLE = 7;
    public static final int METADATA_KEY_YEAR = 8;
    public static final int METADATA_KEY_DURATION = 9;
    public static final int METADATA_KEY_NUM_TRACKS = 10;
    public static final int METADATA_KEY_WRITER = 11;
    public static final int METADATA_KEY_MIMETYPE = 12;
    public static final int METADATA_KEY_ALBUMARTIST = 13;
    public static final int METADATA_KEY_DISC_NUMBER = 14;
    public static final int METADATA_KEY_COMPILATION = 15;
    public static final int METADATA_KEY_HAS_AUDIO = 16;
    public static final int METADATA_KEY_HAS_VIDEO = 17;
    public static final int METADATA_KEY_VIDEO_WIDTH = 18;
    public static final int METADATA_KEY_VIDEO_HEIGHT = 19;
    public static final int METADATA_KEY_BITRATE = 20;
    public static final int METADATA_KEY_LOCATION = 23;
    public static final int METADATA_KEY_VIDEO_ROTATION = 24;
    public static final int METADATA_KEY_CAPTURE_FRAMERATE = 25;
    public static final int METADATA_KEY_HAS_IMAGE = 26;
    public static final int METADATA_KEY_IMAGE_COUNT = 27;
    public static final int METADATA_KEY_IMAGE_PRIMARY = 28;
    public static final int METADATA_KEY_IMAGE_WIDTH = 29;
    public static final int METADATA_KEY_IMAGE_HEIGHT = 30;
    public static final int METADATA_KEY_IMAGE_ROTATION = 31;
    public static final int METADATA_KEY_VIDEO_FRAME_COUNT = 32;
    public static final int METADATA_KEY_EXIF_OFFSET = 33;
    public static final int METADATA_KEY_EXIF_LENGTH = 34;
    public static final int METADATA_KEY_COLOR_STANDARD = 35;
    public static final int METADATA_KEY_COLOR_TRANSFER = 36;
    public static final int METADATA_KEY_COLOR_RANGE = 37;
    public static final int OPTION_PREVIOUS_SYNC = 0;
    public static final int OPTION_NEXT_SYNC = 1;
    public static final int OPTION_CLOSEST_SYNC = 2;
    public static final int OPTION_CLOSEST = 3;

    public MediaMetadataRetriever() {
    }

    public void setDataSource(String path) {
    }

    public void setDataSource(String uri, Map<String, String> headers) {
    }

    public void setDataSource(FileDescriptor fd, long offset, long length) {
    }

    public void setDataSource(FileDescriptor fd) {
    }

    public void setDataSource(Context context, Uri uri) {
    }

    public void setDataSource(MediaDataSource dataSource) {
    }

    public String extractMetadata(int keyCode) {
        return null;
    }

    public Bitmap getFrameAtTime(long timeUs, int option) {
        return null;
    }

    public Bitmap getScaledFrameAtTime(long timeUs, int option, int dstWidth, int dstHeight) {
        return null;
    }

    public Bitmap getFrameAtTime(long timeUs) {
        return null;
    }

    public Bitmap getFrameAtTime() {
        return null;
    }

    public Bitmap getFrameAtIndex(int frameIndex) {
        return null;
    }

    public List<Bitmap> getFramesAtIndex(int frameIndex, int numFrames) {
        return Collections.emptyList();
    }

    public Bitmap getImageAtIndex(int imageIndex) {
        return null;
    }

    public Bitmap getPrimaryImage() {
        return null;
    }

    public byte[] getEmbeddedPicture() {
        return null;
    }

    @Override
    public void close() {
    }

    public void release() {
    }
}
