import java.util.Iterator;
import java.util.List;

@SuppressWarnings("rawtypes")
public final class jP {
    public static ClassCastException s(Iterator it) { return new ClassCastException(); }
    public static String t(int i, int j, String a, String b) { return a + i + b + j; }
    public static String u(int i, String a, String b) { return a + i + b; }
    public static String w(String a, String b) { return a + b; }
    public static String y(StringBuilder sb, List list, char c) { return sb.append(list).append(c).toString(); }
}
