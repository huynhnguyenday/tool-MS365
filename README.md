# Teams Channel Manager

Ứng dụng Windows chạy cục bộ để thêm, gỡ và cập nhật quyền thành viên trong Microsoft Teams và private channel. Giao diện mở trong trình duyệt nhưng backend chỉ lắng nghe tại `127.0.0.1`; thông tin đăng nhập và Microsoft Graph token không được ghi vào repository.

Phiên bản hiện tại: **1.2.0**. Xem [lịch sử phiên bản](CHANGELOG.md) để biết các thay đổi và mốc cập nhật trước đây. File lịch sử cũng có trong gói cài đặt, ở cùng thư mục với launcher.

## Chức năng

- Nút **Làm lại** (mũi tên quay lại cạnh menu công cụ) đưa màn hình hiện tại về trạng thái ban đầu: xóa tìm kiếm, lựa chọn và kết quả đang hiển thị, trả các tùy chọn về mặc định. Tài khoản kết nối, lịch sử thông báo và lựa chọn ở chức năng khác được giữ nguyên; dữ liệu Microsoft 365 đã cập nhật không bị hoàn tác. Nút bị khóa trong khi đang xử lý hoặc xác nhận thao tác.
- Địa chỉ `/#/members` mở quản lý thành viên, `/#/reset-password` mở reset mật khẩu. Tải lại trang vẫn ở đúng chức năng; lựa chọn chỉ lưu trong phiên trang và sẽ xóa khi tải lại. Có thể dùng nút quay lại/tiến tới của trình duyệt để chuyển giữa hai chức năng.

- Liệt kê toàn bộ Team trong tenant dành cho Global Administrator hoặc Teams Administrator.
- Chọn nhiều Team và giữ lựa chọn private channel khi chuyển qua lại giữa các Team.
- Team không chọn private channel: thêm/cập nhật người dùng ở cấp Team với quyền Member hoặc Owner. Thành viên Team tự có quyền truy cập standard channel.
- Team có private channel: kiểm tra thành viên Team cha, yêu cầu xác nhận nếu cần thêm vào Team, sau đó thêm vào private channel với quyền Member hoặc Owner.
- Gỡ thành viên hoặc cập nhật quyền Member/Owner tại cấp Team hoặc private channel. Hai thao tác này chỉ xử lý thành viên hiện có, không tự thêm người vào Team/kênh.
- Phân công dạng cây `Team → Channel → Người dùng → Quyền`.
- Menu công cụ chứa kết nối và cập nhật phiên bản; biểu tượng chuông mở lịch sử thông báo.
- Chọn **Có gì mới** trong menu công cụ để đọc lịch sử cập nhật, kể cả khi offline. Bản đang dùng có nhãn riêng; bản dự kiến được ghi **Sắp phát hành**. Khi phát hiện cập nhật, popup tải thêm ghi chú GitHub và giữ lịch sử cục bộ nếu mạng lỗi.
- Thông báo phân biệt thành công, cảnh báo, lỗi và thông tin; lưu tối đa 100 mục trong phiên hiện tại. Thông báo giống nhau liên tiếp trong 30 giây được gộp lại. Mở chuông để đánh dấu đã đọc; tải lại trang sẽ xóa lịch sử.
- Chọn **Xem chi tiết** trong thông báo kết quả để mở báo cáo của đúng lần chạy đó trên modal có nền mờ. Đóng báo cáo để quay lại lịch sử. Toast có nút đóng, tự ẩn sau 4,2 giây (cảnh báo 7 giây, lỗi 10 giây) và tạm dừng khi rê chuột hoặc đặt focus vào toast.
- Khi thêm thành viên, ứng dụng xử lý lần lượt từng người trong từng Team/kênh và ghi thông báo kết quả sau mỗi yêu cầu. Nút **Xem chi tiết** ở góc dưới phải mở nhật ký lệnh thực tế theo thứ tự: đọc danh sách, kiểm tra thành viên, thêm vào Team cha nếu đã xác nhận, chờ đồng bộ và thêm vào private channel hoặc cập nhật quyền Team. Mỗi lệnh có thời gian, kết quả và lỗi Graph nếu có; người đã thuộc kênh sẽ được bỏ qua mà không gửi lệnh thêm/đổi quyền kênh.
- Nhật ký chỉ lưu trong phiên giao diện, không ghi token hoặc header xác thực vào log và không ghi ra file. Nhật ký có ID tài nguyên và tài khoản của người đang xử lý; tải lại trang sẽ xóa. Nếu mất kết nối trước khi nhận phản hồi, giao diện không thể xác định đầy đủ lệnh đã chạy trên máy chủ. Thông báo thêm thành công vào Team cha được trả về cùng phản hồi xử lý người đó trong kênh, kể cả khi bước đọc thành viên kênh bị lỗi.
- Kiểm tra và tự cập nhật từ nhánh `main` của repository public.
- Sao lưu phiên bản cũ trước mỗi lần cập nhật.

## Yêu cầu

### Reset mật khẩu nhân viên

Sau khi reset, chọn **Xem chi tiết kết quả** hoặc **Xem chi tiết** trong chuông thông báo để đọc báo cáo từng người và toàn bộ lần chạy: kết quả, thời gian, lệnh Graph PATCH và tùy chọn bắt buộc đổi mật khẩu. Mật khẩu trong lệnh hiển thị được thay bằng `[REDACTED]`; báo cáo không ghi token, header xác thực hay nội dung lỗi Graph thô. Báo cáo chỉ lưu trong phiên trang. Nút **Làm lại** xóa báo cáo đang hiển thị nhưng vẫn giữ bản báo cáo trong lịch sử thông báo của phiên đó. Nếu mất kết nối trước khi nhận phản hồi, ứng dụng không thể xác nhận đầy đủ kết quả; cần kiểm tra tài khoản trước khi thử lại.

Ô **Mật khẩu tạm** cho phép nhập hoặc sửa. Bản cài mới không có mật khẩu mặc định; nếu máy có cấu hình cục bộ thì ô được điền sẵn giá trị đó. Khi xác nhận, ứng dụng dùng đúng giá trị đang nhập cho những người đã chọn; không chấp nhận ô trống. Nút **Làm lại** khôi phục giá trị mặc định. Mật khẩu tùy chỉnh chỉ dùng trong yêu cầu reset, không đưa vào kết quả, thông báo hoặc file lưu trữ; Microsoft 365 vẫn kiểm tra chính sách mật khẩu của tổ chức.

Nếu cần tự điền trên máy riêng, tạo file `.local/password-reset.json` trong thư mục ứng dụng với thuộc tính chuỗi `defaultPassword`. File này chứa mật khẩu riêng của máy, được giữ ngoài Git và ZIP; trình cập nhật không ghi đè nó. Không chia sẻ file này cùng gói cài đặt. Cấu hình lỗi không ngăn việc nhập mật khẩu thủ công.

Trong menu công cụ, chọn **Reset mật khẩu**, danh sách toàn bộ nhân viên được tải sẵn theo thứ tự tên (A–Z); lọc bằng tên hoặc email, chọn tài khoản rồi nhấn **Cập nhật mật khẩu** và xác nhận danh sách. Mật khẩu tạm được nhập trong giao diện; checkbox **Bắt buộc đổi mật khẩu ở lần đăng nhập tiếp theo** mặc định tắt; bật nếu muốn yêu cầu nhân viên đổi mật khẩu ở lần đăng nhập tiếp theo. Nút **Làm lại** đưa tùy chọn này về tắt. Tìm kiếm lọc ngay trong danh sách đã tải; nút tải lại cập nhật danh sách từ Microsoft 365. Mỗi lần hỗ trợ tối đa 100 người, có kết quả riêng và giữ lại tài khoản chưa thành công. Kết quả chỉ nằm trong phiên giao diện.

Đăng xuất rồi kết nối lại để cấp thêm quyền delegated `User-PasswordProfile.ReadWrite.All` với sự chấp thuận của quản trị viên. Tài khoản đăng nhập cần vai trò Microsoft Entra được phép reset tài khoản đích; quyền Teams Administrator riêng lẻ không đủ. Microsoft Graph áp dụng giới hạn vai trò và chính sách mật khẩu; tài khoản liên kết liên bang không hỗ trợ luồng này. Xem [tài liệu Microsoft](https://learn.microsoft.com/en-us/graph/api/user-update?view=graph-rest-1.0#example-3-update-the-passwordprofile-of-a-user-and-reset-their-password).

### Môi trường và quyền Teams

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

### Icon và shortcut Windows

Favicon được thiết kế riêng cho tab nhỏ: giữ biểu tượng cửa Office nét đậm, lược bỏ bánh răng để không dính nét khi thu xuống 16 px. Giao diện khai báo `favicon-16.png` và `favicon-32.png` đúng kích thước, kèm `favicon.ico` chứa các khung 16/32/48 px dự phòng. Thuộc tính `type` và `sizes` giúp trình duyệt chọn icon phù hợp ([MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel#icon)). Bản thiết kế gốc nằm trong `favicon-source.png`.

Icon shortcut dùng `toolms-shortcut.ico` có bánh răng và các khung 16–256 px. Shortcut trên Desktop vẫn cần launcher và file icon trong thư mục chương trình; có thể xóa bản `.lnk` dư trong thư mục đó sau khi đã chép ra Desktop. Nếu shortcut cũ trỏ tới `toolms.ico`, đổi đường dẫn icon sang `toolms-shortcut.ico`. Khởi động lại ứng dụng sau khi cập nhật để server phục vụ icon mới; nếu tab vẫn hiện icon cũ, tải lại bằng `Ctrl+F5` hoặc mở tab mới.

Khi làm việc từ mã nguồn repository, chạy `.\Build-Favicon.ps1` để tạo lại favicon từ `favicon-source.png`. Bộ xuất dùng lọc theo diện tích và xử lý alpha để giữ viền khử răng cưa ở 16/32 px; không dùng cách thu ảnh trực tiếp qua `DrawingVisual`. Kiểm tra bằng `.\tests\Test-FaviconAssets.ps1`. Công cụ tạo ảnh này chỉ dùng lúc phát triển, không cần trong gói chạy.

Để tạo shortcut có icon riêng, chạy:

```powershell
.\Create-TeamsChannelManagerShortcut.ps1
```

Script tạo `Teams Channel Manager.lnk` trong thư mục chương trình và không ghi đè shortcut có sẵn. Chép shortcut ra Desktop rồi đổi tên theo ý muốn. Shortcut dùng đường dẫn tuyệt đối tới launcher và `toolms-shortcut.ico`, vì vậy hãy giữ các file chương trình tại vị trí đó.

Nếu đã có shortcut được đổi tên: nhấp phải shortcut → **Properties** → **Shortcut** → **Change Icon** → **Browse**, chọn `toolms-shortcut.ico` trong thư mục chương trình → **OK** → **Apply**. Dùng tên icon mới giúp Windows không tiếp tục dùng ảnh cũ trong bộ nhớ đệm; tên shortcut được giữ nguyên. Windows cho phép đổi icon từng shortcut `.lnk`; file `.cmd` không có thiết lập icon riêng như shortcut.

### Quản lý thành viên

1. Mở **Menu công cụ** (☰), nhấn **Kết nối tài khoản** và đăng nhập Microsoft 365.
2. Tích các Team cần xử lý. Bấm tên Team để xem channel của Team đó.
3. Tích các private channel cần xử lý. Không tích private channel nếu muốn thao tác tại cấp Team/standard channel.
4. Khi **Thêm thành viên**, tìm người dùng trong Microsoft 365. Khi **Cập nhật quyền** hoặc **Gỡ thành viên**, danh sách tự tải người đang thuộc phạm vi đã chọn: có private channel thì lấy thành viên kênh; không chọn kênh thì lấy thành viên Team. Có thể chọn ngay hoặc nhập tên/email/quyền để lọc danh sách.
5. Trong **Tóm tắt thao tác**, chọn **Thêm thành viên**, **Cập nhật quyền** hoặc **Gỡ thành viên**. Khi thêm hoặc cập nhật quyền, mở từng Team và channel rồi chọn Member hoặc Owner cho từng người.
6. Nhấn nút thao tác tương ứng, kiểm tra danh sách và phạm vi rồi xác nhận.

Khung người dùng chia hai cột bằng nhau: bên trái tìm kiếm/chọn thành viên, bên phải hiển thị người đã chọn. Danh sách mỗi cột cuộn riêng; màn hình nhỏ xếp hai cột theo chiều dọc.

Nút biểu tượng **Xóa hết lựa chọn người dùng** cạnh tiêu đề người đã chọn xóa lựa chọn người dùng và ô lọc. Nút biểu tượng **Xóa lựa chọn Team và kênh** cạnh ô tìm Team bỏ toàn bộ Team/kênh đã chọn. Rê chuột để xem tên nút. Các nút màu xám khi không có lựa chọn và chuyển đỏ khi có thể dùng; chúng chỉ đặt lại lựa chọn trên giao diện.

Giao diện dùng Font Awesome Free 6.7.2 đóng gói cục bộ, không cần tải icon từ CDN. Các font Google Sans Flex (tiêu đề), DM Sans (nội dung) và Bricolage Grotesque (nhãn tóm tắt) tải từ Google Fonts; khi không có Internet, giao diện dùng font hệ thống dự phòng. Việc tải font chỉ gửi yêu cầu tài nguyên font, không gửi dữ liệu thành viên trong ứng dụng.

**Cập nhật quyền** chỉ đổi quyền của người đã là thành viên. Người chưa thuộc phạm vi sẽ báo lỗi; người đã có đúng quyền sẽ được bỏ qua. Quyền tại Team và private channel được xử lý riêng.

Danh sách hiện quyền Member/Owner/Guest theo từng Team/kênh, dùng quyền hiện tại làm lựa chọn ban đầu khi cập nhật. Nếu chọn nhiều phạm vi, người dùng được gộp trong danh sách với nhãn quyền riêng cho mỗi phạm vi; chỉ xử lý những phạm vi người đó đang thuộc. Thay đổi Team/kênh sẽ tải lại danh sách và bỏ lựa chọn không còn phù hợp. Nút **Tải lại** làm mới danh sách; ứng dụng cũng tự tải lại sau khi gỡ hoặc đổi quyền. Nếu chưa tải đủ thành viên, ứng dụng chặn thực thi và hiển thị phạm vi bị lỗi.

**Gỡ thành viên** với private channel được chọn chỉ gỡ khỏi các kênh đó, giữ thành viên Team cha. Nếu không chọn private channel trong một Team, thao tác sẽ gỡ khỏi Team, ảnh hưởng quyền truy cập Team và các kênh thuộc Team. Hộp xác nhận liệt kê từng phạm vi và người bị tác động. Người không thuộc phạm vi được bỏ qua. Thao tác không xóa tài khoản Microsoft 365.

Ứng dụng chặn gỡ hoặc hạ quyền Owner cuối cùng tại phạm vi đang xử lý và chặn nâng Guest thành Owner. Microsoft Graph vẫn kiểm tra quyền của tài khoản thao tác và trạng thái thành viên tại thời điểm thực thi. Các thao tác mới sử dụng nhóm quyền Graph đã liệt kê ở trên. Tham khảo API Microsoft: [gỡ thành viên Team](https://learn.microsoft.com/en-us/graph/api/team-delete-members?view=graph-rest-1.0), [gỡ thành viên kênh](https://learn.microsoft.com/en-us/graph/api/channel-delete-members?view=graph-rest-1.0), [đổi quyền Team](https://learn.microsoft.com/en-us/graph/api/team-update-members?view=graph-rest-1.0), [đổi quyền kênh](https://learn.microsoft.com/en-us/graph/api/channel-update-members?view=graph-rest-1.0).

Mỗi Team được xử lý độc lập. Nếu một Team lỗi, kết quả của các Team khác vẫn được giữ lại.

Sau khi xác nhận, phần tóm tắt hiển thị số kênh đã xử lý trên tổng số kênh và Team/kênh đang chạy. Kênh có lỗi vẫn được tính là đã xử lý khi nhận kết quả; kênh bị bỏ qua hoặc chưa chạy không được tính. Luồng không chọn private channel hiển thị tiến độ theo Team.

Khi tác vụ kết thúc, popup kết quả có nền mờ và danh sách cuộn, cho phép lọc thành công, lỗi và mục bỏ qua/đã là thành viên.

- **Đóng & làm mới**: xóa lựa chọn, nội dung tìm kiếm và tải lại danh sách Team; giữ kết nối và lịch sử thông báo.
- **Đóng báo cáo**, nút **×** hoặc **Escape**: chỉ đóng popup, giữ lựa chọn hiện tại. Nhấn **Xem lại kết quả** để mở lại.
- Đóng popup hoặc làm mới không hoàn tác những thay đổi đã thực hiện trên Microsoft 365.

Sau khi cập nhật mã giao diện/server, cần khởi động lại ứng dụng bằng launcher để áp dụng đầy đủ thay đổi.

## Cập nhật tự động

Phiên bản cài đặt nằm trong `VERSION`. Nút **Phiên bản** trong **Menu công cụ** so sánh bản hiện tại với file `VERSION` trên nhánh `main` của repository này.

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

1. Hoàn tất thay đổi; tăng số trong `VERSION` và thêm mục tương ứng lên đầu `CHANGELOG.md` (ngày, chức năng mới, giao diện, sửa lỗi).
2. Chỉ đưa file chương trình/asset cần thiết vào `UPDATE-MANIFEST.txt`; không thêm CSV người dùng, shortcut sinh ra, log hoặc backup.
3. Chạy các bài kiểm tra trong `tests/` và kiểm tra file dự định công khai bằng `.\Test-PublicFiles.ps1` từ repository Git.
4. Tạo ZIP, rồi kiểm tra cả nội dung ZIP: `.\Test-PublicFiles.ps1 -PackagePath .\dist\TeamsChannelManager-1.2.0.zip` (đổi số theo phiên bản đang tạo).
5. Review các file sẽ commit, dùng email GitHub noreply và chỉ push lên `main` khi đã được người quản lý repository cho phép. File `VERSION` trên `main` phải được tăng để máy cũ phát hiện bản mới.
6. Sau khi bản mới có trên GitHub, chạy `.\Update-TeamsChannelManager.ps1 -CheckOnly` để xác nhận phiên bản remote.

Tạo ZIP phát hành:

```powershell
.\Build-Package.ps1
```

File được tạo tại `dist/TeamsChannelManager-<version>.zip`.

Kiểm tra giao diện bằng Chrome với dữ liệu Graph giả lập: `node tests/browser-ui.smoke.cjs` (Node.js 22 trở lên; có thể đặt `CHROME_PATH` nếu Chrome nằm ở đường dẫn khác). Bài kiểm tra dùng trình duyệt headless và hồ sơ tạm, kiểm tra desktop/màn hình hẹp, điều hướng, lựa chọn và báo cáo reset; không kết nối tenant thật.

Repository giữ thêm bài kiểm tra và công cụ/nguồn tạo favicon để bảo trì. ZIP/update chỉ chứa allowlist và CSV mẫu. `Test-PublicFiles.ps1` quét cả file đã track lẫn file mới chưa track, chặn đường dẫn riêng tư và mẫu token/email/ID không phải dữ liệu minh họa; thông báo lỗi chỉ ghi tên file và dòng, không in giá trị bí mật. Quét tự động cần đi cùng review thủ công trước khi công khai.

## Dữ liệu và bảo mật

- Server chỉ bind vào loopback `127.0.0.1`, không mở ra mạng LAN hoặc Internet.
- Microsoft Graph token do module Microsoft quản lý, không được ghi vào source code hoặc ZIP phát hành.
- Không đưa token, client secret, mật khẩu, certificate, file kết quả thật hoặc CSV người dùng thật lên repository.
- `bulk-channel-members.csv` trong repository chỉ chứa địa chỉ mẫu `@contoso.com`.
- `.gitignore` loại trừ ZIP/debug trong `dist/`, backup, `.lnk`, CSV ngoài file mẫu, log, file `.env`, khóa/chứng thư và dữ liệu máy cục bộ. `AGENTS.md` và `UXUI-AGENT.md` chỉ dùng làm hướng dẫn trên máy này.
- Repository public nghĩa là toàn bộ mã nguồn và lịch sử commit đều có thể được đọc công khai.

## Các file chính

- `Open-PrivateChannelMembersUI.cmd`: launcher.
- `Start-PrivateChannelMembersUI.ps1`: local server và Microsoft Graph API.
- `private-channel-members.html`: cấu trúc giao diện và JavaScript.
- `private-channel-members.css`: kiểu dáng và bố cục giao diện.
- `favicon-16.png`, `favicon-32.png`, `favicon.ico`: favicon được tối ưu riêng cho tab trình duyệt; `favicon-source.png` là bản thiết kế gốc, không cần trong gói chạy.
- `toolms-shortcut.ico`: icon cắt sát dùng cho shortcut Windows.
- `Create-TeamsChannelManagerShortcut.ps1`: tạo shortcut `.lnk` có icon riêng. Shortcut sinh ra chỉ dùng trên máy hiện tại, không đưa vào gói cập nhật.
- `fontawesome.min.css`, `fontawesome-solid.min.css`, `fa-solid-900.woff2`: icon Font Awesome Free 6.7.2 được lưu cục bộ; đường dẫn font trong CSS đã điều chỉnh cho gói cài đặt. Nguồn: [Font Awesome](https://github.com/FortAwesome/Font-Awesome/tree/6.7.2). Giấy phép đi kèm trong `FONT-AWESOME-LICENSE.txt`.
- `Update-TeamsChannelManager.ps1`: kiểm tra và cài cập nhật.
- `Build-Package.ps1`: tạo ZIP phát hành.
- `UPDATE-MANIFEST.txt`: danh sách file được cập nhật.
- `VERSION`: phiên bản hiện tại.
- `CHANGELOG.md`: lịch sử thay đổi theo phiên bản, đi kèm bản cập nhật.
- `Test-PublicFiles.ps1`: kiểm tra file dự định công khai và ZIP phát hành, dùng trong repository khi chuẩn bị release.
- `Add-PrivateChannelMembers.ps1`: công cụ PowerShell/CSV truyền thống.

## Tài liệu Microsoft Graph

- [List teams](https://learn.microsoft.com/graph/api/teams-list)
- [List channels](https://learn.microsoft.com/graph/api/channel-list)
- [Add member to team](https://learn.microsoft.com/graph/api/team-post-members)
- [Add member to channel](https://learn.microsoft.com/graph/api/channel-post-members)
