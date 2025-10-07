#!/bin/bash
# Script Otomatis Setup SSH dan Ngrok Native di Linux
#chmod +x setup_native.sh
#./setup_native.sh / bash setup_native.sh

# --- KONFIGURASI PENGGUNA ---
USER_NAME="user1"
USER_PASS="1234" # !! PERINGATAN: GANTI INI DENGAN PASSWORD AMAN ANDA !!
NGROK_TOKEN="TOKEN_KAMU" # !! PERINGATAN: GANTI INI DENGAN TOKEN NGROK ASLI ANDA !!


SSH_PORT="22" # Port default SSH di Linux
NGROK_BIN_DIR="/usr/local/bin"
NGROK_CONFIG_DIR="$HOME/.config/ngrok"
SETUP_MARKER="$HOME/.ngrok_ssh_native_setup_complete"

echo "--- SSH/Ngrok Native Linux Automation Script ---"
echo "Target User: $USER_NAME | Target SSH Port: $SSH_PORT"
echo "---------------------------------------------------"


echo "➡️ Memeriksa dependensi sistem..."


install_package() {
    PACKAGE="$1"
    if ! command -v "$PACKAGE" &> /dev/null; then
        echo "   ❌ '$PACKAGE' tidak ditemukan. Mencoba menginstal..."
        if command -v apt &> /dev/null; then 
            sudo apt update && sudo apt install -y "$PACKAGE"
        elif command -v dnf &> /dev/null; then 
            sudo dnf install -y "$PACKAGE"
        elif command -v pacman &> /dev/null; then 
            sudo pacman -Sy --noconfirm "$PACKAGE"
        else
            echo "   ❌ Gagal menginstal '$PACKAGE'. Distribusi Linux tidak didukung atau butuh instalasi manual."
            exit 1
        fi
        if [ $? -eq 0 ]; then
            echo "   ✅ '$PACKAGE' berhasil diinstal."
        else
            echo "   ❌ Gagal menginstal '$PACKAGE'. Harap periksa koneksi internet/repositori."
            exit 1
        fi
    else
        echo "   ✅ '$PACKAGE' sudah terinstal."
    fi
}

install_package "ssh" 
install_package "wget"
install_package "tar"
install_package "sudo"
install_package "curl"


if ! systemctl is-active --quiet sshd; then
    echo "⚠️ Service SSH (sshd) tidak berjalan. Mencoba memulainya..."
    sudo systemctl enable --now sshd
    if ! systemctl is-active --quiet sshd; then
        echo "❌ Gagal menjalankan service SSH. Harap periksa konfigurasi SSH Anda."
        exit 1
    fi
    echo "✅ Service SSH berhasil dijalankan."
fi

echo "---------------------------------------------------"


if [ ! -f "$SETUP_MARKER" ]; then
    echo "➡️ Melakukan setup awal (User, Ngrok)..."


    if id "$USER_NAME" &>/dev/null; then
        echo "   ⚠️ User '$USER_NAME' sudah ada. Melewati pembuatan user."
       
        echo "$USER_NAME:$USER_PASS" | sudo chpasswd
        echo "   ✅ Password user '$USER_NAME' disetel ulang."
    else
        echo "   ➕ Membuat user baru '$USER_NAME'..."
        sudo useradd -m -s /bin/bash "$USER_NAME"
        echo "$USER_NAME:$USER_PASS" | sudo chpasswd
        sudo usermod -aG sudo "$USER_NAME"
        echo "   ✅ User '$USER_NAME' berhasil dibuat."
    fi

  

   
    ARCH=$(uname -m)
    NGROK_URL=""
    if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "amd64" ]; then
        echo "   Detected Architecture: AMD64"
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
    elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
        echo "   Detected Architecture: ARM64"
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
    else
        echo "   ❌ Arsitektur '$ARCH' tidak didukung untuk Ngrok. Harap instal Ngrok secara manual."
        exit 1
    fi

    
    echo "   ⬇️ Mengunduh dan menginstal Ngrok..."
    cd /tmp
    wget -q "$NGROK_URL" -O ngrok.tgz
    if [ $? -ne 0 ]; then
        echo "   ❌ Gagal mengunduh Ngrok. Harap periksa URL atau koneksi internet."
        exit 1
    fi
    tar -xvzf ngrok.tgz
    sudo mv ngrok "$NGROK_BIN_DIR"/
    sudo chown root:root "$NGROK_BIN_DIR"/ngrok
    sudo chmod +x "$NGROK_BIN_DIR"/ngrok
    echo "   ✅ Ngrok berhasil diinstal ke $NGROK_BIN_DIR/ngrok."

    
    echo "   🔑 Mengkonfigurasi Ngrok Auth Token..."
   
    /usr/local/bin/ngrok config add-authtoken "$NGROK_TOKEN"
    if [ $? -ne 0 ]; then
        echo "   ❌ Gagal mengatur Ngrok Auth Token. Periksa apakah '$NGROK_TOKEN' valid."
        exit 1
    fi
    echo "   ✅ Ngrok Auth Token berhasil diatur."

   
    touch "$SETUP_MARKER"
    echo "✅ Setup awal selesai."
else
    echo "✅ Setup awal sudah selesai. Melewati instalasi user dan Ngrok."
fi

echo "---------------------------------------------------"


echo "SSH Server berjalan di port $SSH_PORT di sistem lokal (ssh $USER_NAME@localhost -p $SSH_PORT)."

echo "Memulai Ngrok TCP Tunnel untuk port SSH ($SSH_PORT)..."
echo "Catatan: Ngrok akan berjalan interaktif. Anda akan melihat alamat tunnel di layar."
echo "Untuk menghentikan Ngrok, tekan Ctrl+C."
echo ""

"$NGROK_BIN_DIR"/ngrok tcp "$SSH_PORT"

echo "Ngrok tunnel dihentikan."

echo "---------------------------------------------------"
echo "Untuk menjalankan kembali Ngrok, jalankan lagi script ini: bash $0"
echo "---------------------------------------------------"