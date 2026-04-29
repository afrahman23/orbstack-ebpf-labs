# eBPF Labs

Repository ini berisi latihan dasar eBPF memakai `bpftrace`, dibagi per level supaya mudah dipraktikkan dari observasi sederhana sampai pengukuran latency syscall.

## Tujuan

1. Memahami bentuk probe `tracepoint` dan `profile`.
2. Memahami variabel bawaan `comm`, `pid`, `tid`, dan `nsecs`.
3. Memahami map `@` untuk menyimpan counter atau state sementara.
4. Mencoba filter berbasis PID dan nama proses.
5. Mengukur latency syscall dengan pasangan `sys_enter_*` dan `sys_exit_*`.

## Prasyarat

1. Linux dengan kernel yang mendukung eBPF.
2. `bpftrace` terpasang.
3. Akses `sudo`.

Cek cepat:

```bash
bpftrace --version
sudo -v
```

## Struktur dan Penjelasan Tiap File

### 1) `level1-basic/cpu.bt`

Isi script:

```bpftrace
profile:hz:99
{
  @[comm] = count();
}
```

Penjelasan argumen dan alasan:

1. `profile:hz:99`
	- Probe sampling periodik berbasis frekuensi, bukan event syscall.
	- `hz:99` artinya sampling 99 kali per detik.
	- Angka 99 sering dipakai agar cukup rapat untuk observasi, namun tidak terlalu berat.
2. `@[comm] = count();`
	- `@` menandakan map/aggregator di bpftrace.
	- `comm` adalah nama command/proses saat sample diambil.
	- `count()` menambah counter per key `comm` untuk melihat proses mana yang paling sering muncul di sample CPU.

Hands-on:

```bash
sudo bpftrace level1-basic/cpu.bt
```

Di terminal lain, buat beban CPU ringan:

```bash
yes > /dev/null
```

Stop beban dengan `Ctrl+C`, lalu stop bpftrace dengan `Ctrl+C` untuk melihat agregat hit.

### 2) `level1-basic/exec.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_execve
{
  printf("CMD: %s\n", str(args->filename));
}
```

Penjelasan argumen dan alasan:

1. `tracepoint:syscalls:sys_enter_execve`
	- Hook ke tracepoint syscall `execve` saat proses akan mengeksekusi program baru.
	- Tracepoint stabil untuk observability karena formatnya disediakan kernel.
2. `args->filename`
	- Mengambil argumen path executable dari event tracepoint.
3. `str(...)`
	- Konversi pointer string kernel/user menjadi string yang aman ditampilkan.
4. `printf(...)`
	- Menampilkan command yang dieksekusi secara realtime.

Hands-on:

```bash
sudo bpftrace level1-basic/exec.bt
```

Di terminal lain, jalankan perintah apa pun, misalnya:

```bash
ls
echo test
```

Output akan menampilkan file executable yang dipanggil.

### 3) `level1-basic/file.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_openat
{
  printf("%s buka file\n", comm);
}
```

Penjelasan argumen dan alasan:

1. `sys_enter_openat`
	- Menangkap event saat proses memanggil `openat` (umum untuk membuka file di Linux modern).
2. `comm`
	- Nama proses yang sedang melakukan open file.
3. `printf("%s buka file\n", comm)`
	- Memberi sinyal cepat proses mana yang melakukan operasi open, cocok untuk latihan awal sebelum menambah detail path file.

Hands-on:

```bash
sudo bpftrace level1-basic/file.bt
```

Di terminal lain:

```bash
cat /etc/hosts
ls /tmp
```

Amati nama proses yang muncul.

### 4) `level1-basic/network.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_connect
{
  printf("%s koneksi network\n", comm);
}
```

Penjelasan argumen dan alasan:

1. `sys_enter_connect`
	- Hook saat proses membuat koneksi socket outbound.
2. `comm`
	- Identifikasi cepat proses pemicu koneksi.
3. `printf(...)`
	- Output realtime untuk validasi aktivitas network dari user-space process.

Hands-on:

```bash
sudo bpftrace level1-basic/network.bt
```

Di terminal lain:

```bash
curl -I https://example.com
```

Script menampilkan nama proses yang melakukan connect.

### 5) `level2-filter/exec_filter.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_execve
/pid == 1234/
{
  printf("PID 1234 jalanin: %s\n", str(args->filename));
}
```

Penjelasan argumen dan alasan:

1. `/pid == 1234/`
	- Predicate/filter supaya event diproses hanya jika PID cocok.
	- Mengurangi noise dan overhead output.
2. PID hardcoded `1234`
	- Bentuk latihan sederhana untuk konsep filter.
	- Untuk praktik nyata, ganti ke PID target saat runtime.

Hands-on:

1. Cari PID target:

```bash
sleep 1000 &
echo $!
```

2. Edit script, ganti `1234` dengan PID di atas.
3. Jalankan script:

```bash
sudo bpftrace level2-filter/exec_filter.bt
```

4. Buat event `execve` dari proses target sesuai skenario uji.

### 6) `level2-filter/network_pid.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_connect
/comm == "curl"/
{
  printf("CURL detected: PID=%d\n", pid);
}
```

Penjelasan argumen dan alasan:

1. `/comm == "curl"/`
	- Filter berdasarkan nama proses, cocok saat PID berubah-ubah.
2. `pid`
	- Tetap dicetak untuk identitas instance proses.
3. String literal `"curl"`
	- Contoh konkret untuk verifikasi cepat aktivitas network dari tool tertentu.

Hands-on:

```bash
sudo bpftrace level2-filter/network_pid.bt
```

Di terminal lain:

```bash
curl -I https://example.com
wget -qO- https://example.com > /dev/null
```

Hanya event dari `curl` yang tercetak.

### 7) `level2-latency/connect_latency.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_connect
{
  @start[tid] = nsecs;
}

tracepoint:syscalls:sys_exit_connect
/@start[tid]/
{
  $delta = nsecs - @start[tid];
  printf("Connect latency: %d us\n", $delta / 1000);
  delete(@start[tid]);
}
```

Penjelasan argumen dan alasan:

1. `@start[tid] = nsecs`
	- Simpan timestamp saat enter.
	- Key pakai `tid` agar aman untuk thread paralel (menghindari tabrakan state antar thread).
2. `sys_exit_connect`
	- Ambil waktu selesai syscall.
3. `/@start[tid]/`
	- Guard agar hanya hitung delta bila state enter ada.
	- Mencegah error logika jika event tidak berpasangan.
4. `$delta = nsecs - @start[tid]`
	- Hitung durasi dalam nanodetik.
5. `$delta / 1000`
	- Konversi ke mikrodetik (`us`) agar lebih mudah dibaca.
6. `delete(@start[tid])`
	- Bersihkan map supaya tidak bocor memory state.

Hands-on:

```bash
sudo bpftrace level2-latency/connect_latency.bt
```

Di terminal lain:

```bash
for i in $(seq 1 5); do curl -I https://example.com > /dev/null 2>&1; done
```

Amati variasi latency connect per panggilan syscall.

### 8) `level2-latency/open_latency.bt`

Isi script:

```bpftrace
tracepoint:syscalls:sys_enter_openat
{
  @start[tid] = nsecs;
}

tracepoint:syscalls:sys_exit_openat
/@start[tid]/
{
  $delta = nsecs - @start[tid];
  printf("File open latency: %d us\n", $delta / 1000);
  delete(@start[tid]);
}
```

Penjelasan argumen dan alasan:

1. Pola sama dengan `connect_latency.bt`, tetapi eventnya `openat`.
2. Mengukur waktu dari enter ke exit syscall file open.
3. Key `tid`, guard map, konversi ke `us`, dan `delete` dipakai untuk konsistensi dan keamanan state.

Hands-on:

```bash
sudo bpftrace level2-latency/open_latency.bt
```

Di terminal lain:

```bash
for i in $(seq 1 10); do cat /etc/hostname > /dev/null; done
```

Amati latency open file pada tiap iterasi.

### 9) `run.sh`

Isi script:

```bash
#!/bin/bash

SCRIPT=$1

if [ -z "$SCRIPT" ]; then
  echo "Usage: ./run.sh <script.bt>"
  exit 1
fi

sudo bpftrace $SCRIPT
```

Penjelasan argumen dan alasan:

1. `SCRIPT=$1`
	- Ambil argumen pertama sebagai path script bpftrace.
2. `[ -z "$SCRIPT" ]`
	- Validasi input kosong, supaya user dapat pesan penggunaan yang jelas.
3. `exit 1`
	- Kode gagal standar ketika input tidak valid.
4. `sudo bpftrace $SCRIPT`
	- Menjalankan script dengan privilege yang umumnya dibutuhkan eBPF.

Hands-on:

```bash
chmod +x run.sh
./run.sh level1-basic/exec.bt
```

## Alur Praktik Disarankan

1. Mulai dari level basic:

```bash
./run.sh level1-basic/exec.bt
./run.sh level1-basic/file.bt
./run.sh level1-basic/network.bt
./run.sh level1-basic/cpu.bt
```

2. Lanjut ke filtering:

```bash
./run.sh level2-filter/network_pid.bt
./run.sh level2-filter/exec_filter.bt
```

3. Terakhir latency:

```bash
./run.sh level2-latency/open_latency.bt
./run.sh level2-latency/connect_latency.bt
```

## Tips Debug Cepat

1. Jika script tidak jalan, cek versi:

```bash
bpftrace --version
uname -r
```

2. Jika ada error permission, jalankan dengan `sudo`.
3. Hentikan tracing dengan `Ctrl+C` agar output agregat/akhir tercetak.

## Cheatsheet Cepat (Terminal)

### Setup

```bash
chmod +x run.sh
bpftrace --version
```

### Jalankan Script

```bash
# format umum
sudo bpftrace <path-script.bt>

# lewat helper
./run.sh level1-basic/exec.bt
```

### Basic Tracing

```bash
./run.sh level1-basic/exec.bt
./run.sh level1-basic/file.bt
./run.sh level1-basic/network.bt
./run.sh level1-basic/cpu.bt
```

### Generate Event Uji

```bash
# memicu execve
ls
echo test

# memicu openat
cat /etc/hosts

# memicu connect
curl -I https://example.com

# memicu sample CPU
yes > /dev/null
```

### Filtering

```bash
# hanya proses curl
./run.sh level2-filter/network_pid.bt

# proses target berdasarkan PID (edit dulu 1234 di script)
sleep 1000 &
echo $!
./run.sh level2-filter/exec_filter.bt
```

### Latency

```bash
./run.sh level2-latency/open_latency.bt
./run.sh level2-latency/connect_latency.bt
```

```bash
# pemicu open latency
for i in $(seq 1 10); do cat /etc/hostname > /dev/null; done

# pemicu connect latency
for i in $(seq 1 5); do curl -I https://example.com > /dev/null 2>&1; done
```

### Berhenti dan Bersih-Bersih

```bash
# stop tracing / workload foreground
Ctrl+C

# stop workload background (contoh: yes)
pkill yes

# cek proses sleep uji filter
ps -ef | grep "sleep 1000"
```

### Troubleshooting Singkat

```bash
# cek kernel dan bpftrace
uname -r
bpftrace --version

# pastikan punya sudo
sudo -v
```# orbstack-ebpf-labs
