#!/bin/bash
# Script Otomatis Setup SSH dan Ngrok Native di Linux
# Dilengkapi Kontrol Granular Konfigurasi SSH dan Kompatibilitas Multi-Init (systemd, SysVinit, dll.).


USER_NAME="user1"
USER_PASS="1234" # !! PERINGATAN: GANTI INI DENGAN PASSWORD AMAN ANDA !!
NGROK_TOKEN="TOKEN_KAMU" # !! PERINGATAN: GANTI INI DENGAN TOKEN NGROK ASLI ANDA !!


AUTO_CONFIG_SSH="true" # <--- UBAH INI MENJADI "false" untuk menonaktifkan modifikasi.


SSH_CONFIG_PORT="22"
SSH_CONFIG_PERMIT_ROOT_LOGIN="yes" # Peringatan: Sangat TIDAK disarankan di host native. Ganti ke "no" untuk keamanan.
SSH_CONFIG_PASSWORD_AUTH="yes"      # Pastikan ini "yes" jika Anda ingin login dengan password.
SSH_CONFIG_EMPTY_PASS="no"
SSH_CONFIG_USE_PAM="yes"


SSH_PORT="22" 
NGROK_BIN_DIR="/usr/local/bin"
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
SETUP_MARKER="$HOME/.ngrok_ssh_native_setup_complete"

echo "--- SSH/Ngrok Native Linux Automation Script (Granular Config) ---"
echo "Target User: $USER_NAME | Opsi Auto-Config SSH: $AUTO_CONFIG_SSH"
echo "-------------------------------------------------------------------"



control_ssh_service() {
    local ACTION=$1 
    local SERVICE_NAME="ssh"

   
    if command -v systemctl &> /dev/null && systemctl status &> /dev/null; then
        local SSHD_UNIT="sshd" 
        if [ "$ACTION" == "status" ]; then
            systemctl is-active --quiet "$SSHD_UNIT" 2>/dev/null
        elif [ "$ACTION" == "start" ]; then
            sudo systemctl start "$SSHD_UNIT"
        elif [ "$ACTION" == "enable" ]; then
            sudo systemctl enable "$SSHD_UNIT"
        elif [ "$ACTION" == "restart" ]; then
            sudo systemctl restart "$SSHD_UNIT"
        fi
        
        if [ $? -eq 0 ]; then return 0; fi
    fi

    
    if command -v service &> /dev/null; then
        if [ "$ACTION" == "status" ]; then
            service "$SERVICE_NAME" status 2>/dev/null
        elif [ "$ACTION" == "start" ] || [ "$ACTION" == "enable" ]; then
            
            sudo service "$SERVICE_NAME" start
        elif [ "$ACTION" == "restart" ]; then
            sudo service "$SERVICE_NAME" restart
        fi
        if [ $? -eq 0 ]; then return 0; fi
    fi

  
    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        if [ "$ACTION" == "status" ]; then
            /etc/init.d/"$SERVICE_NAME" status 2>/dev/null
        elif [ "$ACTION" == "start" ] || [ "$ACTION" == "enable" ]; then
            sudo /etc/init.d/"$SERVICE_NAME" start
        elif [ "$ACTION" == "restart" ]; then
            sudo /etc/init.d/"$SERVICE_NAME" restart
        fi
        if [ $? -eq 0 ]; then return 0; fi
    fi
    
   
    return 1
}



install_package() {
    PACKAGE="$1"
    if ! command -v "$PACKAGE" &> /dev/null && ! dpkg -l | grep -q "^ii.*openssh-server" && ! rpm -q openssh-server &> /dev/null; then
        echo "   ❌ '$PACKAGE' tidak ditemukan. Mencoba menginstal..."
        if command -v apt &> /dev/null; then 
            sudo apt update && sudo apt install -y "$PACKAGE"
        elif command -v dnf &> /dev/null; then 
            sudo dnf install -y "$PACKAGE"
        elif command -v pacman &> /dev/null; then 
            sudo pacman -Sy --noconfirm "$PACKAGE"
        else
            echo "   ❌ Gagal menginstal '$PACKAGE'. Distribusi Linux tidak didukung."
            exit 1
        fi
        if [ $? -eq 0 ]; then
            echo "   ✅ '$PACKAGE' berhasil diinstal."
        else
            echo "   ❌ Gagal menginstal '$PACKAGE'. Harap periksa log."
            exit 1
        fi
    else
        echo "   ✅ '$PACKAGE' sudah terinstal."
    fi
}




echo "➡️ Memeriksa dependensi sistem..."
install_package "openssh-server" 
install_package "wget"
install_package "tar"
install_package "sudo"
install_package "curl"


if ! control_ssh_service "status"; then
    echo "⚠️ Service SSH (sshd) tidak berjalan. Mencoba memulainya..."
    
 
    control_ssh_service "enable"
    control_ssh_service "start"
    
 
    sleep 2
    
    if ! control_ssh_service "status"; then
        echo "❌ Gagal menjalankan service SSH. Harap periksa instalasi dan konfigurasi SSH Anda."
        exit 1
    fi
    echo "✅ Service SSH berhasil dijalankan."
fi

echo "---------------------------------------------------"


set_ssh_config() {
    local KEY=$1
    local VALUE=$2
    if [ -z "$VALUE" ]; then return; fi

  
    if grep -q "^[[:space:]]*#*[[:space:]]*${KEY}[[:space:]]" "$SSHD_CONFIG_FILE"; then
       
        sudo sed -i "s/^[[:space:]]*#*[[:space:]]*${KEY}.*/${KEY} ${VALUE}/" "$SSHD_CONFIG_FILE"
    else
       
        echo "${KEY} ${VALUE}" | sudo tee -a "$SSHD_CONFIG_FILE" > /dev/null
    fi
}



if [ ! -f "$SETUP_MARKER" ]; then
    echo "➡️ Melakukan setup awal (User, Ngrok, Password)..."
    
  
    if id "$USER_NAME" &>/dev/null; then
        echo "   ⚠️ User '$USER_NAME' sudah ada. Melewati pembuatan user."
    else
        echo "   ➕ Membuat user baru '$USER_NAME'..."
        sudo useradd -m -s /bin/bash "$USER_NAME"
        sudo usermod -aG sudo "$USER_NAME"
        echo "   ✅ User '$USER_NAME' berhasil dibuat."
    fi
    
   
    echo "$USER_NAME:$USER_PASS" | sudo chpasswd
    echo "   ✅ Password user '$USER_NAME' disetel/disetel ulang."

  
    ARCH=$(uname -m)
    NGROK_URL=""
    if [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "amd64" ]; then NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz";
    elif [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz";
    else echo "   ❌ Arsitektur '$ARCH' tidak didukung untuk Ngrok."; exit 1; fi

    if [ ! -f "$NGROK_BIN_DIR/ngrok" ]; then
        echo "   ⬇️ Mengunduh dan menginstal Ngrok..."
        cd /tmp
        wget -q "$NGROK_URL" -O ngrok.tgz
        tar -xvzf ngrok.tgz
        sudo mv ngrok "$NGROK_BIN_DIR"/
        sudo chmod +x "$NGROK_BIN_DIR"/ngrok
        echo "   ✅ Ngrok berhasil diinstal."
    else
        echo "   ✅ Ngrok sudah terinstal, melewati pengunduhan."
    fi

    echo "   🔑 Mengkonfigurasi Ngrok Auth Token..."
    /usr/local/bin/ngrok config add-authtoken "$NGROK_TOKEN"
    if [ $? -ne 0 ]; then echo "   ❌ Gagal mengatur Ngrok Auth Token. Periksa token Anda."; exit 1; fi
    echo "   ✅ Ngrok Auth Token berhasil diatur."
    
    touch "$SETUP_MARKER"
    echo "✅ Setup awal user dan Ngrok selesai."
else
    echo "✅ Setup awal (user & Ngrok) sudah selesai. Lanjut ke konfigurasi SSH dan Tunnel."
fi


RESTART_NEEDED=false

if [ "$AUTO_CONFIG_SSH" = "true" ]; then
    echo "➡️ Opsi AUTO_CONFIG_SSH='true' aktif. Memastikan konfigurasi SSHD Host..."
    
 
    if [ ! -f "${SSHD_CONFIG_FILE}.bak_ngrok" ]; then
         sudo cp "$SSHD_CONFIG_FILE" "${SSHD_CONFIG_FILE}.bak_ngrok"
         echo "   💾 Backup /etc/ssh/sshd_config dibuat di ${SSHD_CONFIG_FILE}.bak_ngrok"
    fi

    CONFIGS=(
        "Port $SSH_CONFIG_PORT"
        "PermitRootLogin $SSH_CONFIG_PERMIT_ROOT_LOGIN"
        "PasswordAuthentication $SSH_CONFIG_PASSWORD_AUTH"
        "PermitEmptyPasswords $SSH_CONFIG_EMPTY_PASS"
        "UsePAM $SSH_CONFIG_USE_PAM"
    )

    for CONFIG in "${CONFIGS[@]}"; do
        KEY=$(echo "$CONFIG" | awk '{print $1}')
        EXPECTED_VALUE=$(echo "$CONFIG" | awk '{print $2}' | tr '[:upper:]' '[:lower:]')

        CURRENT_LINE=$(grep "^[[:space:]]*#*[[:space:]]*${KEY}[[:space:]]" "$SSHD_CONFIG_FILE" | head -n 1)
        CURRENT_VALUE=$(echo "$CURRENT_LINE" | awk '{print $2}' | tr '[:upper:]' '[:lower:]' || echo "not_found")
        
       
        if [ "$CURRENT_VALUE" != "$EXPECTED_VALUE" ] || [ "$CURRENT_VALUE" == "not_found" ]; then
            set_ssh_config "$KEY" "$EXPECTED_VALUE"
            echo "      -> '$KEY' diubah menjadi '$EXPECTED_VALUE'."
            RESTART_NEEDED=true
        fi
    done

    
    if [ "$RESTART_NEEDED" = true ]; then
        echo "   🔄 Perubahan terdeteksi. Me-restart service SSHD..."
        control_ssh_service "restart"
        if [ $? -ne 0 ]; then
            echo "   ❌ Gagal me-restart SSHD. Harap periksa log SSHD."
            exit 1
        fi
        echo "   ✅ Konfigurasi SSHD berhasil diterapkan dan di-restart."
    else
        echo "   ✅ Konfigurasi SSHD sudah sesuai dengan skrip. Tidak ada restart."
    fi
else
    echo "➡️ Opsi AUTO_CONFIG_SSH='false'. Konfigurasi SSHD TIDAK diubah. Menggunakan konfigurasi sistem host saat ini."
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