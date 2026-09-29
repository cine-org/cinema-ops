# GCE

> Tạo VM trên Google Compute Engine cho một env. Xong thì làm tiếp [bootstrap/README.md](../../bootstrap/README.md).

Mỗi env nên là một GCP project riêng (quyền, chi phí, secret tách nhau). Chọn đúng project ở thanh trên cùng trước mọi bước.

## 1. Bật Compute Engine API

APIs & Services → Library → **Compute Engine API** → Enable. Project mới phải gắn billing account trước.

## 2. Tạo VM

Compute Engine → VM instances → **Create instance**.

### Machine configuration

| Mục    | Chọn                                                   |
| ------ | ------------------------------------------------------ |
| Name   | `cinema-<env>` (chỉ chữ thường, số, `-`; không có `_`) |
| Region | `asia-southeast1` (Singapore), gần VN nhất             |
| Zone   | Any                                                    |
| Series | E2                                                     |
| Type   | `e2-standard-2` (2 vCPU, 8 GB)                         |

Chọn máy theo tổng RAM các thành phần sẽ chạy: k3s, Argo CD, cert-manager, ESO, Postgres và các app. Loại 4 GB (`e2-medium`, CPU chia sẻ) dễ OOM khi Argo CD sync nhiều app cùng lúc. Swap ở `bootstrap/README.md` chỉ là lưới an toàn, không thay RAM.

### OS and storage

| Mục       | Chọn                           |
| --------- | ------------------------------ |
| OS        | Debian hoặc Ubuntu LTS, x86/64 |
| Disk type | Balanced persistent disk       |
| Size      | ≥ 20 GB                        |

Image container, log k3s và data Postgres (local-path) cùng nằm trên boot disk. Tăng size sau được (Edit disk → Size), không giảm được.

### Data protection

Backups plan → **Snapshot schedules**:

| Mục              | Chọn                    |
| ---------------- | ----------------------- |
| Schedule         | Every day, 1:00–2:00 AM |
| Storage location | `asia` (multi-region)   |
| Retention        | mặc định                |

Snapshot là bản sao cả disk, dùng để dựng lại VM khi hỏng. Không thay backup database: restore snapshot là quay cả máy về thời điểm đó.

### Networking

| Mục                 | Chọn                                                           |
| ------------------- | -------------------------------------------------------------- |
| Allow HTTP traffic  | ✅                                                             |
| Allow HTTPS traffic | ✅                                                             |
| Network interface   | `default`, External IPv4: Ephemeral (đổi sang static ở bước 3) |

Hai ô HTTP/HTTPS gắn tag `http-server`, `https-server` để firewall mặc định của VPC mở 80/443. Port 22 mở sẵn bởi rule `default-allow-ssh`. Firewall VPC nằm ngoài VM; `ufw` trong `bootstrap/README.md` là lớp thứ hai.

### Security

| Mục             | Chọn                   |
| --------------- | ---------------------- |
| Service account | Compute Engine default |
| Access scopes   | Allow default access   |

VM không cần gọi GCP API (ESO đọc GSM bằng SA key riêng, xem `gsm.md`), nên giữ scope mặc định. User `ops` và SSH key làm ở `bootstrap/README.md`.

→ **Create**.

## 3. Static IP

External IP mặc định là **ephemeral**: VM dừng thì GCP thu IP lại, lần bật sau cấp IP khác, DNS và SSH trỏ nhầm. Chuyển sang static khi VM **đang chạy**:

VPC network → IP addresses → External IP addresses → dòng `Ephemeral` của VM → ⋮ → **Promote to static IP address** → Name `cinema-<env>-ip` → Reserve.

Sau đó trỏ bản ghi A của env (Cloudflare, DNS only) và `HostName` trong `~/.ssh/config` về IP này.

Static IP tính tiền theo giờ, kể cả khi VM tắt. Xoá VM thì vào lại trang này → ⋮ → **Release static address**.

## 4. Lịch tắt/bật (tuỳ chọn)

Tắt VM những giờ không dùng để giảm tiền máy. Disk và static IP vẫn tính tiền khi tắt.

### Tạo schedule

Compute Engine → VM instances → tab **Instance schedules** → **Create schedule**:

| Mục        | Chọn              |
| ---------- | ----------------- |
| Name       | ví dụ `night-off` |
| Region     | trùng region VM   |
| Start/Stop | giờ bật / giờ tắt |
| Time zone  | `Asia/Saigon`     |
| Frequency  | Every day         |

Mở schedule vừa tạo → **Add instances to schedule** → chọn VM.

### Cấp quyền cho schedule

Schedule chạy bằng service agent của Compute Engine, mặc định agent này không có quyền start/stop VM.

IAM & Admin → IAM → **Grant access**:

| Mục       | Giá trị                                                           |
| --------- | ----------------------------------------------------------------- |
| Principal | `service-<PROJECT_NUMBER>@compute-system.iam.gserviceaccount.com` |
| Role      | **Compute Instance Admin (v1)**                                   |

Thiếu quyền này thì thêm VM vào schedule sẽ báo lỗi.

### Khi VM tắt/bật theo lịch

- k3s tự chạy lại khi VM lên (systemd), Argo CD tự sync.
- Webhook GitHub gửi lúc VM tắt sẽ fail; Argo CD vẫn poll Git định kỳ nên tự bắt kịp.
- Không đặt lịch cho env đã có người dùng thật.

## Verify

```bash
ssh "$HOST" 'hostname; nproc; free -h; df -h /'
```

Khớp tên VM, số CPU, RAM, disk. Tắt/bật VM một lần: external IP không đổi.
