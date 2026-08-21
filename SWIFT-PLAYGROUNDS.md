# LensLab trên Swift Playgrounds (iPad)

Đây là bản native SwiftUI dành cho iPad. Không cần Mac hoặc Xcode để chạy thử trên iPad.

## Mở dự án

1. Tải [LensLab-Playgrounds-ready-v2.zip](./LensLab-Playgrounds-ready-v2.zip) về iPad.
2. Mở ứng dụng **Files**, chạm vào file ZIP để giải nén.
3. Chạm vào thư mục `LensLab.swiftpm` rồi chọn **Open in Swift Playgrounds**.
4. Chờ Playgrounds tải dự án, sau đó bấm nút **Run**.
5. Khi iPad hỏi quyền, chọn **Allow** cho Camera và Photos.

Dự án yêu cầu iPadOS 17 trở lên. Nếu Swift Playgrounds báo cần cập nhật, hãy cập nhật ứng dụng và iPadOS trước.

## Kết nối máy ảnh

- Dùng camera tích hợp: chọn **Camera sau** hoặc **Camera trước** trong menu camera.
- Dùng Nikon D5500 hoặc máy ảnh khác: nối HDMI của máy ảnh vào capture card, rồi nối capture card vào cổng USB-C của iPad.
- Bật Live View trên máy ảnh. Trong LensLab, mở menu camera và chọn thiết bị có tên capture card.
- Nếu thiết bị chưa xuất hiện, mở lại menu và chọn **Tìm lại camera**.

Nút chụp chỉ bật khi phiên camera đã chạy. LensLab lấy khung hình hiện tại từ luồng video nên tương thích với cả capture card UVC (không yêu cầu card phải hỗ trợ chụp ảnh tĩnh). Sau khi chụp, LensLab tự chuyển sang màn hình chỉnh ảnh. Các thao tác chỉnh màu, LUT, làm mịn da và xoá/làm mờ nền chạy ngay trên iPad bằng Core Image và Vision. Nút **Lưu ảnh** ghi kết quả vào Photos.

## AI Cloud (tuỳ chọn)

AI Cloud cần API token và model version tương thích Replicate. Có thể bỏ qua phần này; camera, chỉnh ảnh cơ bản và lưu Photos vẫn hoạt động offline.

## Giới hạn thực tế

- Capture card phải hỗ trợ UVC và được iPadOS nhận diện; một số card cần hub USB-C có cấp nguồn.
- Độ phân giải phụ thuộc tín hiệu HDMI/capture card (thường tối đa 1080p).
- Không có Mac/Xcode trong quy trình này, nhưng để phát hành lên App Store vẫn cần tài khoản Apple Developer và quy trình ký ứng dụng riêng.
