# Lịch sử phiên bản — Teams Channel Manager

Ghi các thay đổi đáng chú ý của từng phiên bản, mới nhất ở trên. Phiên bản chương trình nằm trong `VERSION`; máy đã cài đặt chỉ phát hiện cập nhật sau khi phiên bản mới có trên GitHub `main`.

## 1.2.0 — 2026-10-31

- Thêm màn hình reset mật khẩu Microsoft 365: tải sẵn toàn bộ danh sách nhân viên theo thứ tự tên, lọc và chọn nhiều người, xác nhận danh sách và xem kết quả từng người.
- Cho phép sửa mật khẩu tạm và bật/tắt yêu cầu đổi mật khẩu ở lần đăng nhập tiếp theo (mặc định tắt); giữ lại tài khoản chưa reset thành công để kiểm tra.
- Đồng bộ bố cục, checkbox và nút tìm kiếm/xóa lựa chọn giữa hai chức năng; giữ menu công cụ và chuông thông báo trên màn hình hẹp.
- Giữ đúng chức năng đang mở khi tải lại trang; thêm nút Làm lại cạnh menu để xóa lựa chọn và kết quả của màn hình hiện tại, giữ kết nối và lịch sử thông báo.
- Thông báo reset có báo cáo chi tiết từng người, tổng hợp thành công/lỗi và nhật ký Graph đã che mật khẩu; mở lại từ chuông thông báo hoặc nút Xem chi tiết kết quả.
- Mật khẩu mặc định chỉ lưu trong cấu hình cục bộ, không nằm trong mã nguồn hoặc gói cài; bản cài mới yêu cầu nhập mật khẩu trước khi reset.

## 1.1.1 — 2026-10-31

### Chức năng mới

- Thêm **Có gì mới** để xem lịch sử cập nhật, đọc được cả khi offline.

### Cải tiến giao diện

- Đồng bộ font Google Sans Flex, chia đều hai khung Team/người dùng và thu gọn bố cục.
- Làm rõ bộ lọc, checkbox, menu công cụ và các nút thông báo.
- Rút gọn nhãn thành viên; chuyển hướng dẫn vào nút thông tin cạnh tiêu đề.

### Cải tiến tải dữ liệu

- Giảm tải trùng danh sách thành viên khi chọn nhiều kênh.
- Rút gọn ghi chú cập nhật; đọc lại changelog mỗi lần mở Có gì mới.

## 1.1.0 — 2026-10-31

- Thêm gỡ thành viên và đổi quyền Member/Owner tại Team, private channel.
- Tải thành viên hiện có, hiển thị quyền theo từng Team/kênh.
- Chặn gỡ Owner cuối cùng và nâng Guest thành Owner.
- Bổ sung báo cáo kết quả, tiến độ và nhật ký xử lý từng người.
- Cải tiến giao diện chọn người dùng, thông báo và nút xóa lựa chọn.
- Thêm icon ứng dụng, favicon và lịch sử phiên bản trong gói cài đặt.

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
