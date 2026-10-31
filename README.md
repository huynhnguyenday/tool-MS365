# Teams Channel Manager

Công cụ Windows quản lý thành viên Team/private channel và reset mật khẩu Microsoft 365. Chạy cục bộ tại `http://127.0.0.1:8765`, kết nối Microsoft Graph bằng tài khoản của bạn.

## Cài đặt và mở ứng dụng

1. Tải ZIP tại [Releases](https://github.com/huynhnguyenday/tool-MS365/releases), giải nén vào thư mục cố định.
2. Cài module một lần trong PowerShell: `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`.
3. Nhấp đúp `Setup.cmd`: chương trình tự tạo icon **Teams Channel Manager** trên Desktop. Từ lần sau, nhấp đúp icon đó để mở tool.

Chạy lại `Setup.cmd` để sửa shortcut tiêu chuẩn nếu bị lỗi hoặc sau khi chuyển thư mục ứng dụng; shortcut đã đổi tên được giữ nguyên. Hỗ trợ Desktop đồng bộ OneDrive. Giữ cửa sổ PowerShell trong khi dùng, nhấn `Ctrl+C` để dừng. Hỗ trợ Windows PowerShell 5.1 và PowerShell 7.

Đổi cổng: `powershell.exe -ExecutionPolicy Bypass -File .\app\Start-PrivateChannelMembersUI.ps1 -Port 8766`. Launcher `Open-PrivateChannelMembersUI.cmd` được giữ để shortcut cũ tiếp tục hoạt động.

## Sử dụng

- **Thành viên:** kết nối Microsoft 365 → chọn Team/kênh → chọn thao tác và người dùng → kiểm tra tóm tắt → xác nhận.
- **Không chọn private channel:** thao tác tại cấp Team. **Có chọn kênh:** chỉ thao tác trên kênh; khi thêm người chưa thuộc Team cha, ứng dụng hỏi trước khi thêm họ vào Team với quyền Member.
- **Đổi quyền/gỡ:** chọn từ thành viên hiện có; chặn gỡ/hạ quyền Owner cuối cùng và nâng Guest thành Owner. Gỡ khỏi Team ảnh hưởng quyền truy cập Team và các kênh thuộc Team.
- **Reset mật khẩu:** mở từ menu, chọn tối đa 100 người, nhập mật khẩu và xác nhận. Yêu cầu đổi mật khẩu lần đăng nhập sau mặc định tắt. Quyền reset phụ thuộc vai trò quản trị và chính sách tenant.
- **Kết quả:** xem báo cáo từng người hoặc mở lại từ chuông thông báo. **Làm lại** xóa lựa chọn/kết quả của chức năng hiện tại, giữ kết nối và lịch sử.

## Quyền Microsoft Graph

Quản trị viên cần chấp thuận các quyền delegated:

- Đọc: `Team.ReadBasic.All`, `Channel.ReadBasic.All`, `User.ReadBasic.All`.
- Thành viên: `ChannelMember.Read.All`, `ChannelMember.ReadWrite.All`, `TeamMember.Read.All`, `TeamMember.ReadWriteNonOwnerRole.All`, `TeamMember.ReadWrite.All`.
- Reset mật khẩu: `User-PasswordProfile.ReadWrite.All`, kèm vai trò quản trị phù hợp.

## Cập nhật

Mở **Phiên bản** trong menu → kiểm tra → xác nhận. Chương trình tải từ GitHub `main`, sao lưu vào `.update-backup/` và khởi động lại. Xem [lịch sử thay đổi](CHANGELOG.md).

Thủ công: `powershell.exe -File .\Update-TeamsChannelManager.ps1 -CheckOnly`; thay `-CheckOnly` bằng `-Apply -Restart` để cài. CSV và `.local/` không bị ghi đè. Khi chuyển cấu trúc, file chương trình cũ được sao lưu rồi dọn; icon gốc được giữ cho shortcut cũ.

## Cấu trúc

```text
app/           Server và giao diện, icon, font trong web/
scripts/       Tạo shortcut và công cụ CSV truyền thống
Setup.cmd      Tự tạo/sửa shortcut trên Desktop
Update-*.ps1   Kiểm tra và cài cập nhật
```

`VERSION`, manifest, tài liệu và CSV mẫu nằm ở gốc. GitHub/ZIP chỉ chứa bộ chạy và tài liệu/giấy phép cần thiết. Tests, công cụ bảo trì và ảnh nguồn giữ trong `.dev/` trên máy phát triển, không đưa vào Git/ZIP.

Luồng CSV: `scripts/Add-PrivateChannelMembers.ps1`; xem tham số bằng `Get-Help .\scripts\Add-PrivateChannelMembers.ps1 -Full`. `bulk-channel-members.csv` là mẫu email, không phải file gán Team/kênh đầy đủ.

## Dữ liệu

Server chỉ lắng nghe `127.0.0.1`. Không chia sẻ token, mật khẩu, CSV thật, báo cáo hoặc `.local/`. Bản cài mới không có mật khẩu mặc định; cấu hình riêng chỉ lưu tại `.local/password-reset.json`, không tự lưu mật khẩu đã dùng. Font chữ có thể tải từ Google Fonts; icon Font Awesome đi kèm giấy phép trong `app/web/FONT-AWESOME-LICENSE.txt`.
