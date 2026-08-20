# LensLab — Studio máy ảnh cho iPad

App web (PWA) kết nối máy ảnh qua capture card HDMI→USB-C, chụp rồi **tự động chỉnh ảnh bằng AI** (nhận diện khuôn mặt, làm mịn da, sáng mắt, cân sáng/white balance), thêm **bộ lọc màu (LUT)**, **cắt/xoay/nắn thẳng** và **mở ảnh RAW** ngay trên iPad. Xuất ảnh về iPad hoặc tải thẳng lên **Google Drive**. Không cần Mac, Xcode hay tài khoản Apple Developer.

## Vì sao phải "host" lên mạng thay vì mở file trực tiếp?

Trình duyệt chỉ cho phép truy cập camera khi trang được tải qua **https://**. Mở file HTML trực tiếp từ Files app (địa chỉ `file://`) sẽ **không** xin được quyền camera. Vì vậy cần đưa các file này lên một địa chỉ https:// — cách miễn phí, dễ nhất và làm được hoàn toàn từ iPad là **GitHub Pages**.

## Cách host bằng GitHub Pages (làm trên iPad, ~5 phút)

1. Mở **github.com** bằng Safari, đăng ký tài khoản miễn phí nếu chưa có.
2. Nhấn dấu **+** ở góc trên → **New repository**. Đặt tên (vd `lenslab`), để chế độ **Public**, nhấn **Create repository**.
3. Trong repo vừa tạo, nhấn **"uploading an existing file"** (hoặc Add file → Upload files).
4. Chọn **tất cả** các file trong thư mục này: `index.html`, `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png`, `apple-touch-icon.png` và tải lên cùng lúc (giữ nguyên tên file, không để trong thư mục con).
5. Cuộn xuống, nhấn **Commit changes**.
6. Vào tab **Settings** của repo → mục **Pages** ở thanh bên trái.
7. Ở **Build and deployment → Source**, chọn **Deploy from a branch**; **Branch** chọn `main` và thư mục `/ (root)` → **Save**.
8. Đợi khoảng 1–2 phút, trang sẽ hiện link dạng:
   `https://<tên-tài-khoản>.github.io/lenslab/`

## Cài lên màn hình chính iPad

1. Mở link trên bằng **Safari** (bắt buộc là Safari, không phải Chrome/khác).
2. Cho phép quyền **Camera** khi được hỏi.
3. Nhấn nút **Chia sẻ** (hình vuông mũi tên lên) trên thanh địa chỉ → **Add to Home Screen** → **Add**.
4. Từ giờ mở app như một app bình thường từ màn hình chính.

## Quy trình sử dụng

1. Cắm mini-HDMI (máy ảnh) → HDMI → capture card → USB-C (iPad).
2. Bật Live View hoặc quay phim trên D5500 để máy ảnh phát tín hiệu HDMI.
3. Mở app → **Kết nối máy ảnh** → cho phép quyền camera → chọn đúng thiết bị (capture card) trong danh sách nếu có nhiều camera.
4. Bấm nút chụp (nút tròn) để chụp khung hình hiện tại.
5. App **tự động chỉnh ảnh bằng AI** ngay sau khi chụp: cân phơi sáng/tương phản/white balance, nhận diện khuôn mặt để retouch theo vùng. Bạn chỉnh tay thêm ở các tab: **Ánh sáng** (phơi sáng, tương phản, highlights/shadows, độ rõ, vignette), **Màu sắc** (bão hoà, ấm/lạnh, tint, hạt film), **Làm mịn** (da, sáng mắt, tẩy trắng răng, xoá mắt đỏ, giảm quầng thâm, má hồng, làm nét), **LUT** (11 bộ lọc + nhập file .cube), **Cắt** (crop/xoay/nắn thẳng). Hoặc nhấn "Tự động" để chạy lại AI.
6. Xuất ảnh: **Lưu về iPad** (JPG vào Files/Photos) hoặc **⬆ Drive** (tải lên Google Drive — cần cài Client ID ở ⚙ Cài đặt, xem bên dưới). Làm bước này trước khi thoát app vì ảnh chỉ lưu tạm trong bộ nhớ.

## Mở ảnh RAW (NEF, ARW, CR2, DNG…)

Nhấn **Chọn ảnh (JPG / RAW)** ở màn hình chính rồi chọn file RAW từ Files app. App dùng **dcraw** (port Emscripten, chạy ngay trong Safari) để giải mã:

- Hỗ trợ NEF (Nikon), CR2/ARW (Canon/Sony), DNG, RAF (Fujifilm), ORF (Olympus), RW2 (Panasonic), PEF (Pentax)…
- Lần đầu mở RAW cần mạng để tải thư viện (~1–2 MB); các lần sau có thể dùng offline.
- Ảnh RAW được giải mã ở **nửa độ phân giải** (~3000×2000 với D5500) để chạy mượt trên iPad, dùng camera white balance + khử highlight bị cháy. Sau khi mở, bạn chỉnh sửa và xuất như ảnh thường.

> Lưu ý: dcraw.js là port cũ (2017) nên **không** hỗ trợ định dạng rất mới như Canon **CR3**. Nikon D5500 (NEF) hỗ trợ tốt.

## Xuất lên Google Drive (bắt buộc làm 1 lần)

Để bật nút **⬆ Drive**, cần tạo một **OAuth Client ID** miễn phí từ Google Cloud rồi dán vào app. Làm hoàn toàn trên iPad, ~5 phút:

1. Mở **console.cloud.google.com** (đăng nhập tài khoản Google của bạn).
2. Tạo **project mới** (menu chọn project ở thanh trên → **New project** → đặt tên, vd `lenslab` → Create). Chờ vài giây rồi chọn project đó.
3. Bật API: menu trái **APIs & Services → Library** → tìm **Google Drive API** → nhấn **Enable**.
4. Cấu hình màn hình đồng ý: **APIs & Services → OAuth consent screen** → chọn **External** → Create. Điền tên app (vd LensLab) và email của bạn; các mục còn lại để mặc định. Ở mục **Test users** thêm chính email Google của bạn (bắt buộc, vì app chưa được Google xác minh).
5. Tạo credentials: **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type chọn **Web application**.
6. Ở mục **Authorized JavaScript origins**, nhấn **Add URI** và nhập đúng origin của trang GitHub Pages của bạn (lưu ý: chỉ gồm scheme + host, **không có đường dẫn**):

   `https://<tên-tài-khoản>.github.io`

7. Nhấn **Create** → sao chép chuỗi **Client ID** (dạng `xxxxx.apps.googleusercontent.com`).
8. Trong app LensLab, nhấn biểu tượng **⚙** trên thanh trên cùng → dán Client ID → **Lưu Client ID**.

Từ giờ, khi nhấn **⬆ Drive**, lần đầu Google sẽ hỏi bạn cho phép truy cập — chọn tài khoản của bạn và **Cho phép**. App sẽ hiện cửa sổ **chọn thư mục**: bạn duyệt vào thư mục muốn lưu (hoặc để mặc định My Drive) rồi nhấn **Lưu vào thư mục này**. Ảnh được tải lên dưới dạng file JPG (`lenslab-....jpg`); thư mục đã chọn sẽ được ghi nhớ cho lần sau.

> Lưu ý: để liệt kê thư mục và chọn nơi lưu, app dùng quyền `drive` (đọc/ghi trong Drive của chính bạn). Nếu lần đầu đăng nhập không mở được cửa sổ cho phép ở chế độ app đã cài (Add to Home Screen), hãy mở bằng tab Safari thường để cấp quyền lần đầu, sau đó dùng bình thường.

## Giới hạn hiện tại (và hướng nâng cấp)

- **Mượt (không giật):** khi chỉnh sửa, app xử lý ảnh ở bản xem trước (≤1440px) nên cắt/xoay/thanh trượt chạy mượt; khi xuất, ảnh được render lại ở độ phân giải đầy đủ (đến 4096px). Do đó thao tác không bị trễ, chỉ lúc xuất mới mất vài giây.
- **AI nhận diện khuôn mặt** chạy ngay trong trình duyệt bằng MediaPipe Face Landmarker (478 điểm landmark). Nó làm mịn da + sáng mắt theo từng vùng mặt. Model tải từ CDN (~vài MB) ở **lần đầu tiên** và cần mạng; sau đó dùng offline được. Khi ảnh không có mặt, app tự chuyển về chế độ cân sáng/white balance.
- **LUT** gồm 11 bộ lọc có sẵn (được tạo ngay trong app, dùng offline) + nhập file **.cube** bên ngoài. Cường độ điều chỉnh bằng thanh trượt.
- **RAW** giải mã bằng dcraw.js (WASM/asm.js) ở nửa độ phân giải để mượt; hỗ trợ NEF/ARW/CR2/DNG… nhưng chưa hỗ trợ CR3. Có thể nâng cấp lên thư viện mới hơn (libraw wasm) để full-res + CR3.
- Ảnh chụp chỉ lưu tạm trong phiên (RAM), chưa lưu vĩnh viễn trong app — có thể nâng cấp bằng IndexedDB để giữ ảnh qua các lần mở app.
- Độ phân giải phụ thuộc capture card (thường 1080p); D5500 xuất HDMI tối đa 1080p nên không mất gì so với tín hiệu gốc.
- Đôi khi Safari có bug nhỏ về getUserMedia khi chạy ở chế độ "đã cài đặt" (standalone) sau các bản cập nhật iPadOS — nếu camera không lên sau khi cài vào màn hình chính, thử mở lại bằng tab Safari thường để xác nhận, và cập nhật iPadOS lên bản mới nhất.
- Xuất Google Drive cần mạng và Client ID (xem mục trên); chưa hỗ trợ tạo thư mục theo buổi chụp — có thể nâng cấp sau.

## Muốn nâng cấp lên app gốc (native) sau này?

Nếu sau này có Mac, toàn bộ logic xử lý ảnh (các hàm trong `index.html`) có thể chuyển sang Swift/Core Image gần như 1:1. Hoặc nếu chưa có Mac, có thể dùng **Swift Playgrounds** ngay trên iPad để viết app SwiftUI + AVFoundation thật, dùng `AVCaptureDevice` loại `.external` để đọc trực tiếp từ capture card — có thể chạy thử ngay trong Swift Playgrounds mà không cần Mac.
