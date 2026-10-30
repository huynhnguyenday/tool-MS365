# Lịch sử phiên bản — Teams Channel Manager

Ghi các thay đổi đáng chú ý của từng phiên bản, mới nhất ở trên. Phiên bản chương trình nằm trong `VERSION`; máy đã cài đặt chỉ phát hiện cập nhật sau khi phiên bản mới có trên GitHub `main`.

## 1.1.0 — 2026-10-31

### Chức năng mới

- Gỡ thành viên hoặc cập nhật quyền Member/Owner tại cấp Team và private channel.
- Khi gỡ/đổi quyền, tự tải thành viên và quyền hiện tại theo phạm vi đã chọn; ô tìm kiếm lọc danh sách này. Chế độ thêm vẫn tìm người trong Microsoft 365.
- Với nhiều phạm vi, hiển thị quyền riêng ở từng Team/kênh và chỉ xử lý những phạm vi người được chọn đang thuộc.
- Chặn gỡ/hạ quyền Owner cuối cùng, nâng Guest thành Owner và gửi thao tác mới tới server chưa hỗ trợ.
- Nhật ký lệnh Graph theo thứ tự cho từng người, gồm kiểm tra thành viên, thêm vào Team cha sau xác nhận, chờ đồng bộ, thêm/gỡ/đổi quyền và lỗi thực thi.

### Giao diện và thông báo

- Làm mới bố cục, tách CSS khỏi HTML và giữ khả năng dùng trên màn hình nhỏ.
- Khung người dùng chia hai cột 50/50: tìm kiếm/chọn và người đã chọn, cuộn riêng.
- Thêm nút xóa toàn bộ lựa chọn người dùng và Team/kênh; màu xám khi chưa chọn, đỏ khi có thể dùng.
- Dùng Font Awesome Free cục bộ; Google Sans Flex cho tiêu đề, DM Sans cho nội dung và Bricolage Grotesque cho nhãn tóm tắt, có font dự phòng.
- Mở rộng bảng thông báo, làm rõ viền/màu thành công, cảnh báo và lỗi; sửa đếm chưa đọc, gộp mục lặp và giới hạn toast.
- Báo kết quả từng người khi hoàn tất. Nút Xem chi tiết mở modal trên nền mờ, giữ đúng báo cáo của từng lần chạy.
- Bổ sung tiến độ xử lý, lọc kết quả và thao tác bàn phím trong hộp xác nhận/thông báo.

### Icon và favicon

- Thêm icon riêng cho shortcut Windows, công cụ tạo `.lnk` và hướng dẫn đổi icon của shortcut đã đặt tên.
- Tạo favicon riêng cho tab: PNG 16/32 px và ICO 16/32/48 px, cập nhật URL để tránh cache cũ.
- Sửa lỗi xuất ảnh gây răng cưa bằng bộ thu ảnh theo diện tích, xử lý alpha; có kiểm tra hồi quy cho cạnh chéo và viền trong suốt.
- Gộp icon shortcut vào `toolms-shortcut.ico`, bỏ file ảnh trùng `toolms.ico`; giữ URL web cũ làm alias. Shortcut cũ trỏ trực tiếp tới file ảnh cũ cần chọn lại icon theo README.

### Bảo trì và phát hành

- Thêm lịch sử phiên bản này vào gói cập nhật và liên kết trong README.
- Giữ bài kiểm tra và nguồn thiết kế trong repository; gói cài đặt chỉ gồm file trong allowlist và CSV mẫu.
- Dọn file thử nghiệm; mở rộng loại trừ dữ liệu máy cục bộ, shortcut, log, CSV thật và thông tin xác thực.

## 1.0.3 — 2026-10-29

- Cải tiến UX, menu công cụ và vị trí điều khiển kết nối/cập nhật.
- Chuông mở bảng lịch sử thông báo.

## 1.0.2 — 2026-10-26

- Điều chỉnh bố cục chọn Team/kênh, bộ lọc và nút chọn tất cả.
- Rút gọn tên Team/kênh dài, giữ tên đầy đủ trong tooltip; điều chỉnh trạng thái mở cây tóm tắt.

## 1.0.1 — 2026-10-26

- Sửa tương thích Windows PowerShell cho tham số mặc định của trình cập nhật và công cụ đóng gói.
- Bật TLS 1.2 cho bước kiểm tra/tải cập nhật.

## 1.0.0 — 2026-10-26

- Bản đóng gói đầu tiên: giao diện cục bộ quản lý thành viên Team/private channel qua Microsoft Graph.
- Phân công Member/Owner, kiểm tra Team cha và xác nhận trước khi thêm người còn thiếu.
- Tự cập nhật từ GitHub `main`, sao lưu trước cập nhật và cung cấp ZIP cài đặt.

## Cách ghi cho phiên bản tiếp theo

Khi chuẩn bị phát hành, thêm mục phiên bản mới ở trên, ghi ngày và chỉ những thay đổi người dùng cần biết. Có thể chia thành **Chức năng mới**, **Giao diện**, **Sửa lỗi**, **Bảo trì** khi phù hợp. Không sửa/xóa ghi chú phiên bản cũ để thay cho mục mới; không ghi dữ liệu tenant, người dùng hoặc thông tin xác thực vào lịch sử.

Các mục 1.0.0–1.0.3 được tổng hợp từ những commit phát hành trong repository; không bao gồm mọi thay đổi nhỏ của từng commit.
