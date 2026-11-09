public final class ir {
    public static String C(int i, int j, String a, String b, String c) { return a + i + b + j + c; }
    public static String D(String a, String b, String c) { return a + b + c; }
    public static String E(StringBuilder sb, String a, String b) { return sb.append(a).append(b).toString(); }
    public static StringBuilder F(String a, String b) { return new StringBuilder().append(a).append(b); }
    public static void I(AutoCloseable c) { if (c != null) try { c.close(); } catch ( Throwable ignored) {} }
    public static void K(StringBuilder sb, int i, String a, String b, String c) { sb.append(i).append(a).append(b).append(c); }
    public static StringBuilder P(String a, String b) { return new StringBuilder().append(a).append(b); }
    public static void Q(StringBuilder sb, int i, String a, String b, String c) { sb.append(i).append(a).append(b).append(c); }
}
