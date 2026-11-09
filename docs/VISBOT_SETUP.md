# Mina Visbot v2.0 — Hướng dẫn cài đặt

Robot: **UBTECH Visbot** (MediaTek MT8167, Android 8.1, màn 308×240, camera trước, không có GPS).
App ID: `com.mtc.mina_visbot` (cài song song được với bản Robonova `com.mtc.mina_robot`).

## 1. Cài app

```powershell
adb install -r Mina_Visbot_v2.0.0_release.apk
adb shell pm grant com.mtc.mina_visbot android.permission.RECORD_AUDIO
adb shell pm grant com.mtc.mina_visbot android.permission.CAMERA
```

Đặt Mina làm màn hình chính: trong Mina mở **Cài đặt Mina → Mina là màn hình chính**, chọn *Mina Visbot*.
Muốn quay lại launcher gốc: Cài đặt Android → Ứng dụng → Ứng dụng mặc định → Ứng dụng màn hình chính → *Visbot*.

> Lưu ý: khi Mina làm màn hình chính, launcher gốc của Visbot (`com.ubtech.visbot`) không còn ở màn hình chính.
> Các dịch vụ hệ thống của robot (`com.ubtrobot.*`) vẫn chạy. Cần thử thực tế xem robot còn tự di chuyển như trước không.

## 2. Ghép nối các trợ lý trên xiaozhi.me

Mỗi trợ lý là **một thiết bị riêng** trên xiaozhi.me:

| Trợ lý | Gợi ý giọng |
| :--- | :--- |
| Mina | Nữ tiếng Việt trẻ, vui vẻ |
| Gia sư Toán | Tiếng Việt rõ ràng |
| Gia sư Văn | Nữ tiếng Việt dịu dàng |
| Gia sư Tiếng Anh | Tiếng Anh bản xứ (Mỹ/Anh), ưu tiên giọng đa ngôn ngữ |
| Kể chuyện | Tiếng Việt ấm, chậm |

Với từng trợ lý:
1. Trên xiaozhi.me tạo một **agent** mới, chọn giọng theo bảng trên.
2. Dán nội dung **Vai trò** (xem trong app: Cài đặt Mina → bấm vào trợ lý → Sao chép; hoặc trong `lib/models/assistant_profile.dart`).
3. Trong Mina chọn trợ lý đó (menu ứng dụng) → màn hình hiện **mã 6 số** → trên xiaozhi.me thêm thiết bị bằng mã đó vào agent vừa tạo.

Chưa xác minh: số agent tối đa của tài khoản miễn phí, và danh sách giọng tiếng Anh cụ thể trên xiaozhi.me.

## 3. Lệnh giọng nói mẫu

- "Mina ơi, cho gặp gia sư Toán" / "học tiếng Anh" / "kể chuyện cho bé"
- "Mở VOV3", "tắt radio"
- "Mở YouTube nhạc thiếu nhi"
- "Tìm tin tức hôm nay", "đọc trang vnexpress.net"
- "Nhìn bài tập này" / "Cái này là gì?" (chụp camera; cần server XiaoZhi gửi cấu hình vision)

## 4. Bánh xe và đầu của Visbot

Chuyển động do dịch vụ hệ thống **ROSA** của UBTECH điều khiển (`/locomotor/locomote`, `/servo/rotate`, `/motion/action/perform`).
Quyền gọi dịch vụ là `com.ubtrobot.permission.ROBOT` với mức bảo vệ **signature**: chỉ app ký bằng khóa của UBTECH mới được cấp.
Mina **không** lách cơ chế này. Robot tiếp tục tự di chuyển theo chương trình gốc.

Muốn Mina điều khiển được, cần UBTECH cung cấp SDK/khóa ký. Thư mẫu gửi người bán hoặc UBTECH:

> Chào anh/chị,
> Tôi đang dùng robot UBTECH **Visbot** (model `Visbot`, serial `A10053SNZA029A1401786`, Android 8.1, hệ thống ROSA: `Master_Rosa`, `Visbot_SystemServices_Rosa`).
> Tôi muốn phát triển ứng dụng riêng điều khiển bánh xe và đầu robot qua dịch vụ ROSA (`/locomotor/locomote`, `/servo/rotate`).
> Dịch vụ yêu cầu quyền `com.ubtrobot.permission.ROBOT` (mức signature). Xin hỏi UBTECH có chương trình nhà phát triển, ROSA SDK,
> hoặc cách ký ứng dụng / firmware dành cho nhà phát triển cho Visbot không?
> Cảm ơn anh/chị.

**Tiếng Trung (gửi UBTECH / người bán Trung Quốc):**

> 您好，我有一台优必选 **Visbot** 机器人（型号 Visbot，序列号 A10053SNZA029A1401786，Android 8.1，ROSA 系统）。
> 我想开发自己的应用，通过 ROSA 服务（`/locomotor/locomote`、`/servo/rotate`）控制机器人的轮子和头部。
> 该服务需要 `com.ubtrobot.permission.ROBOT` 权限（signature 级别）。请问优必选是否提供 Visbot 的开发者计划、ROSA SDK，
> 或开发者签名 / 开发版固件？谢谢！
