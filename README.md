# Mina AI Robot (`com.mtc.mina_robot`)

Ứng dụng điều khiển giọng nói và cử động chuyên biệt dành cho **Robot Hình Người Hàn Quốc (Robonova-II / Metal Fighter)** sử dụng **Board ngực Android Allwinner A33 (32-bit ARMv7 + Mảng 4 Mic ZNJ V1.0)** kết nối với **Mạch Servo MR-C3024FX**.

---

## 1. Các Tính Năng Đã Tích Hợp Sẵn (Không Giới Hạn Tài Khoản / VIP)

1. **Đánh Thức Giọng Nói Offline (TinyML Sherpa-ONNX)**:
   - Chạy trực tiếp trên chip Allwinner A33 không cần mạng bằng model nén `int8` (`assets/models/kws/`).
   - Các câu gọi đánh thức đã cấu hình sẵn trong [keywords.txt](assets/models/kws/keywords.txt):
     - **"Mina"**
     - **"Chào Mina"**
     - **"Hey Mina"**
     - **"Mina ơi"**
2. **Đàm Thoại Thời Gian Thực Chuẩn XiaoZhi + Nén Âm Thanh Opus (`libopus.so`)**:
   - Kết nối trực tiếp tới máy chủ chính thức `wss://api.tenclass.net/xiaozhi/v1/` bằng **địa chỉ MAC độc lập của riêng Robot Mina** (quản lý miễn phí 100% trên `https://xiaozhi.me`, không qua bất kỳ cổng thu phí trung gian nào).
   - Hỗ trợ đổi sang máy chủ XiaoZhi tự dựng nội bộ (`ws://IP_LAN:8000/...`) ngay trong ngăn kéo cài đặt.
3. **Tích Hợp Máy Chủ MCP Nội Bộ (`MinaMcpServer`) Với Đầy Đủ 63 Động Tác (`K1`–`K68`) & Đọc Cảm Biến Trực Tiếp**:
   - Đối chiếu chính xác 100% bảng mã `DEC 40` (`'('`) đến `DEC 108` (`'l'`) ở tốc độ **UART 2 chiều `9600` baud** (`ERX 9600` & `ETX 9600`) trên mạch `MR-C3024FX`.
   - Khi anh trò chuyện với Mina (*"Mina ơi cúi chào đi"*, *"Phía trước có vật cản không?"*, *"Còn bao nhiêu pin?"*, *"Mina múa võ đi"*, *"Nhảy Break Dance cho anh xem"*), AI tự động gọi các MCP tool (`self.mina.greet`, `self.mina.walk`, `self.mina.read_sensors`, `self.mina.set_safety_reflex`, `self.mina.martial_arts`, `self.mina.dance_and_acrobatics`, `self.mina.posture_and_standup`, `self.mina.perform_any_action`).
   - Hỗ trợ **3 phản xạ tự hành thông minh**:
     1. Tự động dừng bước tiến / lùi tránh va chạm khi cảm biến siêu âm (`< 25 cm`) hoặc cảm biến 10k (`ADC > 85`) phát hiện vật cản.
     2. Tự động vẫy tay chào (`K7`) & mở phiên trò chuyện khi mắt siêu âm phát hiện có người đứng trước mặt (`15–65 cm`).
     3. Tự động đứng dậy (`K19` / `K25`) khi cảm biến nghiêng `AD(5)` phát hiện ngã ngửa hoặc ngã sấp.
4. **Khuôn Mặt Hoạt Hình 60FPS, Bảng Theo Dõi Cảm Biến & Bảng Test 63 Động Tác**:
   - Hiển thị mắt biểu cảm (Bình thường, Lắng nghe, Suy nghĩ, Vui vẻ `^ ^`, Thả tim, Múa võ), thanh sóng âm và huy hiệu thông số **Mắt siêu âm / Cảm biến 10k / Điện áp Pin** thời gian thực.
   - Bấm biểu tượng góc phải trên để mở **Trung Tâm Điều Khiển Robot MINA**: xem trực tiếp thông số cảm biến, bật/tắt phản xạ tự hành, test từng nút `K1`–`K68` không cần mạng, chọn cổng `/dev/ttyS1` / `/dev/ttyS2` và xem log trực tiếp.

---

## 2. Sơ Đồ Đấu Dây Cảm Biến & UART 2 Chiều Trên Mạch Robonova-II (`MR-C3024FX`)

### 2.1. Sơ đồ cắm Cảm Biến Siêu Âm (Mắt) & Cảm Biến Khoảng Cách 10k vào Mạch Đỏ `MR-C3024FX`

Theo tập lệnh phần cứng của trình biên dịch `roboBASIC MF v2.80` (dành cho mạch `MR-C3024FX`), lệnh `SONAR(port)` chỉ hỗ trợ `port = 0..7` (tương ứng các chân Digital `#0..#15`). Do robot đã dùng 16 servo tại `#0..#4`, `#6..#8`, `#12..#14`, `#18..#22`, cặp chân **`#10` & `#11` (`SONAR(5)`)** trên cụm `G6B` (gần cổ/vai trái) là cặp chân phần cứng chuẩn duy nhất còn trống cho cảm biến siêu âm:

| Cảm biến trên Robot | Cổng trên Mạch `MR-C3024FX` | Ký hiệu trong `roboBASIC MF` | Ghi chú đấu dây (`G - V - S`) |
| :--- | :--- | :--- | :--- |
| **Cảm biến siêu âm trên mắt (4 chân)** | **Port `#10`** (Trigger) & **Port `#11`** (Echo) trên cụm **`B` (`G6B`)** | `SONAR(5)` | `VCC` -> hàng giữa `V` (`5V`), `GND` -> hàng ngoài `G`, `Trig` -> chân `S` của `#10`, `Echo` -> chân `S` của `#11` *(Nếu dùng siêu âm Analog 3 chân thì cắm vào `AD1` và đổi `CONST US_USE_AD = 1`)* |
| **Cảm biến đo khoảng cách 10k (Analog)** | **`AD0`** trên cụm góc phải trên (`AD0..AD7`) | `AD(0)` | `G` -> `GND`, `V` -> `5V`, dây tín hiệu (giữa cầu phân áp 10k / Analog Out) -> chân `S` của `AD0` (`AD1..AD4` vẫn còn trống) |
| **Cảm biến nghiêng / chống ngã** | **`AD5`** | `AD(5)` | `< 30`: ngã ngửa -> `K19`, `> 200`: ngã sấp -> `K25`. **Mặc định TẮT** (chương trình gốc đã comment `robot_tilt`); chỉ bật công tắc "Tự động đứng dậy" trong app khi đã cắm cảm biến nghiêng |
| **Đo điện áp Pin 6V** | **`AD6`** | `AD(6)` | Có sẵn trên mạch (`Điện áp = AD(6) * 10 / 256`, cảnh báo khi `< 5.8V`) |

### 2.2. Sơ đồ đấu dây UART 2 Chiều (3 dây) giữa Board Ngực Android A33 & Mạch `MR-C3024FX`

Để vừa điều khiển 63 động tác (`TX -> ERX`), vừa đọc dữ liệu cảm biến gửi từ `MR-C3024FX` lên màn hình Android (`ETX -> RX`), nối **3 dây** giữa cụm `J8 (5V - T - R - G)` / `UART1` trên board đen **Allwinner A33** và cụm `ETX / ERX` góc trái trên của mạch đỏ **`MR-C3024FX`**:

| Chân trên Board Android A33 | Chân trên Mạch Servo `MR-C3024FX` | Chức năng (`9600` baud, 8N1) |
| :--- | :--- | :--- |
| **`T` (`TX`)** | **`ERX`** | Android gửi mã động tác (`40..108`) và lệnh hỏi cảm biến `'s'` (`115`), bật/tắt phản xạ `'m'`/`'n'` (`109`/`110`) |
| **`R` (`RX`)** | **`ETX`** | `MR-C3024FX` truyền gói 8 byte `[0xAA, 0x55, SonarHi, SonarLo, Dist10k, Batt, Tilt, Chk]` lên Android |
| **`G` (`GND`)** | **`GND`** | Bắt buộc nối chung Mass (`GND`) giữa 2 mạch (**Không** nối chân `5V` giữa 2 mạch) |

### 2.3. Nạp chương trình cảm biến cho Mạch `MR-C3024FX`
1. Mở phần mềm **`roboBASIC MF`** (chọn `Set -> Controller -> MR-C3024FX Serial`, đúng cổng `COM`).
2. Mở file firmware đã tích hợp sẵn toàn bộ 63 động tác + đọc cảm biến siêu âm & 10k:
   [robonova_firmware/code_robonova2_mina_sensors.bas](robonova_firmware/code_robonova2_mina_sensors.bas)
3. Nhấn **Compile (`F6`)** & **Download (`F7`)** xuống mạch `MR-C3024FX`.

---

## 3. Cách Xuất File APK (`Mina_AI_release.apk`) & Cài Vào Robot

### Cách A: Tự động xuất APK trên đám mây bằng GitHub Actions (Không cần cài Android Studio 10GB vào máy tính)
1. Đẩy thư mục `E:\MTC\APK\MinaRobot` lên một GitHub Repository cá nhân của anh.
2. File workflow [.github/workflows/build_apk.yml](.github/workflows/build_apk.yml) sẽ tự động biên dịch bản Release hỗ trợ cả `armeabi-v7a` (32-bit cho chip Allwinner A33) và `arm64-v8a` (64-bit cho điện thoại).
3. Vào tab **Actions** -> tải file **`Mina_AI_v1.0.0_release.apk`** về máy.

### Cách B: Build trực tiếp trên máy tính (nếu cài Flutter SDK + Android SDK)
```powershell
cd E:\MTC\APK\MinaRobot
flutter create --platforms=android --org com.mtc --project-name mina_robot .
flutter pub get
flutter build apk --release
```

### Cài đặt vào Board Android A33 qua cáp Micro-USB (sử dụng `C:\platform-tools\adb.exe` có sẵn trên máy anh):
```powershell
powershell -ExecutionPolicy Bypass -File E:\MTC\APK\MinaRobot\install_to_robot.ps1
```

---

## 4. Kích Hoạt Giọng Nói Miễn Phí Lần Đầu Trên `xiaozhi.me`
1. Mở app **Mina AI** trên Robot (đã kết nối Wi-Fi).
2. Màn hình sẽ hiện **Mã ghép nối 6 chữ số** của riêng Mina.
3. Anh đăng nhập vào `https://xiaozhi.me` -> tạo Agent đặt tên là **Mina**, chọn ngôn ngữ **Tiếng Việt**, giọng nói tùy thích và nhập **mã 6 chữ số** để thêm thiết bị.
4. Trong phần *System Prompt (Vai trò nhân vật)* trên `xiaozhi.me`, anh có thể dặn thêm:
   > *"Bạn là Mina, một cô bé robot hình người thông minh, đáng yêu. Khi người dùng yêu cầu cử động, chào hỏi, đi lại, nhảy múa hoặc biểu diễn võ thuật, hãy luôn gọi các công cụ MCP `self.mina.*` để điều khiển cơ thể thật của mình."*
