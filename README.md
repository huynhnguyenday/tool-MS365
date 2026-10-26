# Teams Channel Manager

Ứng dụng Windows chạy cục bộ để thêm nhiều người dùng vào nhiều Microsoft Teams và private channel. Giao diện mở trong trình duyệt nhưng backend chỉ lắng nghe tại `127.0.0.1`; thông tin đăng nhập và Microsoft Graph token không được ghi vào repository.

## Chức năng

- Liệt kê toàn bộ Team trong tenant dành cho Global Administrator hoặc Teams Administrator.
- Chọn nhiều Team và giữ lựa chọn private channel khi chuyển qua lại giữa các Team.
- Team không chọn private channel: thêm/cập nhật người dùng ở cấp Team với quyền Member hoặc Owner. Thành viên Team tự có quyền truy cập standard channel.
- Team có private channel: kiểm tra thành viên Team cha, yêu cầu xác nhận nếu cần thêm vào Team, sau đó thêm vào private channel với quyền Member hoặc Owner.
- Phân công dạng cây `Team → Channel → Người dùng → Quyền`.
- Toast thông báo và lịch sử thông báo trong biểu tượng chuông.
- Kiểm tra và tự cập nhật từ nhánh `main` của repository public.
- Sao lưu phiên bản cũ trước mỗi lần cập nhật.

## Yêu cầu

- Windows PowerShell 5.1 hoặc PowerShell 7.
- Tài khoản Microsoft 365 cơ quan/trường học.
- Microsoft Graph PowerShell Authentication:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

- Quyền delegated Microsoft Graph được quản trị viên chấp thuận:
  - `Team.ReadBasic.All`
  - `Channel.ReadBasic.All`
  - `ChannelMember.Read.All`
  - `ChannelMember.ReadWrite.All`
  - `TeamMember.Read.All`
  - `TeamMember.ReadWriteNonOwnerRole.All`
  - `TeamMember.ReadWrite.All`
  - `User.ReadBasic.All`

`TeamMember.ReadWrite.All` cần thiết khi thêm hoặc đổi người dùng thành Owner ở cấp Team.

## Khởi chạy

Nhấp đúp `Open-PrivateChannelMembersUI.cmd`. Ứng dụng mặc định mở tại `http://127.0.0.1:8765`. Giữ cửa sổ PowerShell chạy trong thời gian sử dụng; nhấn `Ctrl+C` để dừng.

Nếu cổng 8765 đang được sử dụng:

```powershell
.\Open-PrivateChannelMembersUI.cmd 8766
```

## Cách sử dụng

1. Nhấn **Kết nối tài khoản** và đăng nhập Microsoft 365.
2. Tích các Team cần xử lý. Bấm tên Team để xem channel của Team đó.
3. Tích các private channel cần cấp quyền. Không tích private channel nếu chỉ muốn thêm vào Team/standard channel.
4. Tìm và chọn người dùng.
5. Trong **Tóm tắt thao tác**, mở từng Team và channel rồi chọn Member hoặc Owner cho từng người.
6. Nhấn **Thêm thành viên**, kiểm tra danh sách và xác nhận.

Mỗi Team được xử lý độc lập. Nếu một Team lỗi, kết quả của các Team khác vẫn được giữ lại.

## Cập nhật tự động

Phiên bản cài đặt nằm trong `VERSION`. Nút phiên bản cạnh biểu tượng chuông so sánh bản hiện tại với file `VERSION` trên nhánh `main` của repository này.

Khi có phiên bản mới, ứng dụng sẽ:

1. Yêu cầu xác nhận.
2. Tải ZIP của nhánh `main` từ GitHub.
3. Kiểm tra `UPDATE-MANIFEST.txt` và từ chối đường dẫn không an toàn.
4. Sao lưu file hiện tại vào `.update-backup/`.
5. Chỉ thay các file chương trình có trong manifest.
6. Tự khởi động lại.

`bulk-channel-members.csv` không được cập nhật đè để tránh mất dữ liệu người dùng.

Kiểm tra hoặc cập nhật thủ công:

```powershell
.\Update-TeamsChannelManager.ps1 -CheckOnly
.\Update-TeamsChannelManager.ps1 -Apply -Restart
```

## Phát hành phiên bản mới

1. Sửa mã nguồn và tăng số trong `VERSION`, ví dụ `1.0.0` thành `1.1.0`.
2. Kiểm tra cú pháp và chạy thử.
3. Commit rồi push lên nhánh `main`.
4. Máy đang dùng bản cũ sẽ phát hiện bản mới qua nút phiên bản.

Tạo ZIP phát hành:

```powershell
.\Build-Package.ps1
```

File được tạo tại `dist/TeamsChannelManager-<version>.zip`.

## Dữ liệu và bảo mật

- Server chỉ bind vào loopback `127.0.0.1`, không mở ra mạng LAN hoặc Internet.
- Microsoft Graph token do module Microsoft quản lý, không được ghi vào source code hoặc ZIP phát hành.
- Không đưa token, client secret, mật khẩu, certificate, file kết quả thật hoặc CSV người dùng thật lên repository.
- `bulk-channel-members.csv` trong repository chỉ chứa địa chỉ mẫu `@contoso.com`.
- `.gitignore` loại trừ `dist/`, `.update-backup/` và `private-channel-results-*.csv`.
- Repository public nghĩa là toàn bộ mã nguồn và lịch sử commit đều có thể được đọc công khai.

## Các file chính

- `Open-PrivateChannelMembersUI.cmd`: launcher.
- `Start-PrivateChannelMembersUI.ps1`: local server và Microsoft Graph API.
- `private-channel-members.html`: giao diện.
- `Update-TeamsChannelManager.ps1`: kiểm tra và cài cập nhật.
- `Build-Package.ps1`: tạo ZIP phát hành.
- `UPDATE-MANIFEST.txt`: danh sách file được cập nhật.
- `VERSION`: phiên bản hiện tại.
- `Add-PrivateChannelMembers.ps1`: công cụ PowerShell/CSV truyền thống.

## Tài liệu Microsoft Graph

- [List teams](https://learn.microsoft.com/graph/api/teams-list)
- [List channels](https://learn.microsoft.com/graph/api/channel-list)
- [Add member to team](https://learn.microsoft.com/graph/api/team-post-members)
- [Add member to channel](https://learn.microsoft.com/graph/api/channel-post-members)
