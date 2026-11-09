import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.os.Build;

public final class h30 {
    @SuppressWarnings("deprecation")
    public static Notification.Builder c(Service s) {
        if (Build.VERSION.SDK_INT >= 26) {
            return new Notification.Builder(s, "ubtrobot");
        }
        return new Notification.Builder(s);
    }

    public static void u(NotificationManager nm, NotificationChannel ch) {
        if (Build.VERSION.SDK_INT >= 26 && nm != null && ch != null) {
            nm.createNotificationChannel(ch);
        }
    }
}
