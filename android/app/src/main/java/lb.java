import android.util.Log;

public final class lb {
    public static String s(StringBuilder sb, int i, char c) { return sb.append(i).append(c).toString(); }
    public static String t(StringBuilder sb, String a, String b, String c) { return sb.append(a).append(b).append(c).toString(); }
    public static void z(String a, String b, String c) { Log.w(c, a + b); }
}
