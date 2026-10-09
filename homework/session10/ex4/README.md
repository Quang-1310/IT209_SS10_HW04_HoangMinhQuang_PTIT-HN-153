Bài tập triển khai thủ công hai container bằng Docker CLI:

- `app-container`: web server tối giản chạy từ image `python:3.12-alpine`.
- `db-server`: PostgreSQL 15 chạy từ image `postgres:15-alpine`.
- `app-net`: custom bridge network cung cấp DNS nội bộ giữa hai container.
- `db-data`: named volume lưu dữ liệu PostgreSQL bền vững.

Backend nhận thông tin kết nối qua các biến môi trường `DB_HOST`, `DB_PORT`,
`DB_NAME`, `DB_USER`, `DB_PASSWORD` và `DATABASE_URL`. Trong đó hostname database
là tên container `db-server`, không phải địa chỉ IP cố định.

## Yêu cầu môi trường

- Docker Engine hoặc Docker Desktop đang chạy.
- Shell tương thích POSIX như Bash, Git Bash hoặc WSL.
- Các lệnh `grep` và `chmod` (có sẵn trong Git Bash/WSL/Linux/macOS).

## Chạy bài

Mở terminal tại thư mục `homework/session_10/ex4/`, sau đó chạy:

```bash
chmod +x commands.sh
./commands.sh
```

Script thực hiện lần lượt:

1. Tạo custom bridge network `app-net` và named volume `db-data` nếu chưa có.
2. Khởi chạy PostgreSQL và chờ database sẵn sàng.
3. Khởi chạy backend trong cùng network, với `DB_HOST=db-server`.
4. Ping `db-server` từ backend để kiểm tra Docker DNS.
5. Tạo bảng và thêm một marker kiểm thử vào PostgreSQL.
6. Xóa cứng `db-server`, tạo lại container với cùng volume `db-data`.
7. Truy vấn marker và kết thúc với mã lỗi nếu dữ liệu không còn.

Script giữ lại hai container sau khi chạy để có thể kiểm tra thủ công. Script cũng
có thể chạy lại; container cũ được tái tạo nhưng named volume không bị xóa.

## Kiểm tra thủ công

```bash
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net
docker exec -it app-container ping -c 2 db-server
```

Kiểm tra dữ liệu đã lưu:

```bash
docker exec -it db-server psql -U appuser -d appdb \
  -c "SELECT * FROM persistence_test;"
```

Kết quả thành công gồm thông báo `Persistence test passed`, lệnh ping phân giải
được `db-server` thành IP nội bộ, và bảng `persistence_test` vẫn chứa marker sau
khi database container được tái tạo.

## Dọn dẹp

Xóa hai container và network nhưng giữ dữ liệu:

```bash
docker rm -f app-container db-server
docker network rm app-net
```

Chỉ xóa volume khi không còn cần dữ liệu PostgreSQL:

```bash
docker volume rm db-data
```

> Lưu ý: `docker volume rm db-data` xóa vĩnh viễn dữ liệu của bài thực hành.