import android.app.NotificationChannel;
import android.os.Build;

public final class Xw {
    public static NotificationChannel e() {
        if (Build.VERSION.SDK_INT >= 26) {
            return new NotificationChannel("ubtrobot", "UBTECH Robot Service", 2);
        }
        return null;
    }

    public static void i(NotificationChannel ch) {
    }
}
