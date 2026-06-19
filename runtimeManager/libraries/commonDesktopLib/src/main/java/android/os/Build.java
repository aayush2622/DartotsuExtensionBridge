package android.os;

/**
 * Dartotsu version - no config dependency
 */
public class Build {

    public static final boolean IS_DEBUGGABLE = false;

    public static final String BOARD = "generic";
    public static final String BOOTLOADER = "unknown";
    public static final String BRAND = "dartotsu";
    @Deprecated public static final String CPU_ABI = "x86_64";
    @Deprecated public static final String CPU_ABI2 = "";
    public static final String DEVICE = "dartotsu";
    public static final String DISPLAY = "dartotsu-user";
    public static final String FINGERPRINT = "dartotsu/generic/generic:11/TEST/1:user/release-keys";
    public static final String HARDWARE = "generic";
    public static final String HOST = "localhost";
    public static final String ID = "DARTOTSU";
    public static final String MANUFACTURER = "dartotsu";
    public static final String MODEL = "Dartotsu VM";
    public static final String PRODUCT = "dartotsu";
    @Deprecated public static final String RADIO = "unknown";
    public static final String SERIAL = "unknown";
    public static final String[] SUPPORTED_32_BIT_ABIS = new String[] { "x86" };
    public static final String[] SUPPORTED_64_BIT_ABIS = new String[] { "x86_64" };
    public static final String[] SUPPORTED_ABIS = new String[] { "x86_64", "x86" };
    public static final String TAGS = "release-keys";
    public static final long TIME = System.currentTimeMillis();
    public static final String TYPE = "user";
    public static final String UNKNOWN = "unknown";
    public static final String USER = "dartotsu";

    private Build() {
        throw new RuntimeException("This class cannot be instantiated!");
    }

    public static String getRadioVersion() {
        return "unknown";
    }

    // ---- Version codes ----
    public static class VERSION_CODES {
        public static final int BASE = 1;
        public static final int BASE_1_1 = 2;
        public static final int CUPCAKE = 3;
        public static final int DONUT = 4;
        public static final int ECLAIR = 5;
        public static final int ECLAIR_0_1 = 6;
        public static final int ECLAIR_MR1 = 7;
        public static final int FROYO = 8;
        public static final int GINGERBREAD = 9;
        public static final int GINGERBREAD_MR1 = 10;
        public static final int HONEYCOMB = 11;
        public static final int HONEYCOMB_MR1 = 12;
        public static final int HONEYCOMB_MR2 = 13;
        public static final int ICE_CREAM_SANDWICH = 14;
        public static final int ICE_CREAM_SANDWICH_MR1 = 15;
        public static final int JELLY_BEAN = 16;
        public static final int JELLY_BEAN_MR1 = 17;
        public static final int JELLY_BEAN_MR2 = 18;
        public static final int KITKAT = 19;
        public static final int KITKAT_WATCH = 20;
        public static final int LOLLIPOP = 21;
        public static final int LOLLIPOP_MR1 = 22;
        public static final int M = 23;
        public static final int N = 24;
        public static final int N_MR1 = 25;
        public static final int O = 25;
        public static final int CUR_DEVELOPMENT = 10000;
    }

    // ---- Version info ----
    public static class VERSION {
        public static final String BASE_OS = "";
        public static final String CODENAME = "REL";
        public static final String INCREMENTAL = "1";
        public static final int PREVIEW_SDK_INT = 0;
        public static final String RELEASE = "11";
        @Deprecated public static final String SDK = "30";
        public static final int SDK_INT = 30;
        public static final String SECURITY_PATCH = "2023-01-01";

        private VERSION() {
            throw new RuntimeException("Stub!");
        }
    }
}