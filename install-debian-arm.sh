#!/data/data/com.termux/files/usr/bin/bash

# URL base para las descargas boot
base_url="https://deb.debian.org/debian/dists/trixie/main/installer-armhf/current/images/netboot/"

# URL iso net
base_url_iso="https://cdimage.debian.org/debian-cd/current/armhf/iso-cd/"
base_filename="debian-13.0.0-armhf-netinst.iso"

# Archivos a descargar boot
files=("vmlinuz" "initrd.gz")

# Paquetes a instalar en Termux
paquetes=("qemu-utils" "qemu-system-arm" "wget" "p7zip")

# Instalar paquetes (si falla uno, continua con el siguiente)
for pkg in "${paquetes[@]}"; do
    if ! pkg list-installed | grep -q "$pkg"; then
        if ! pkg install -y "$pkg" &> /dev/null; then
            echo "Error instalando $pkg, pero continuando..."
        fi
    fi
done

# Descargar archivos boot (si falla uno, continua con el siguiente)
for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "El archivo $file ya existe, omitiendo descarga"
    else
        if wget -c "${base_url}${file}" &> /dev/null; then
            echo "$file descargado exitosamente"
        else
            echo "Error descargando $file, pero continuando..."
        fi
    fi
done

# Descargar ISO
if [[ -f "$base_filename" ]]; then
    echo "El archivo $base_filename ya existe, omitiendo descarga"
else
    # Intentar descargar versión 13.0.0
    if wget -c --quiet --show-progress "${base_url_iso}${base_filename}"; then
        echo "Versión 13.0.0 descargada exitosamente"
    else
        # Si falla, buscar la versión más actual
        echo "Buscando versión más actual..."
        base_filename=$(wget -qO- "$base_url_iso" | grep -o 'debian-[0-9.]*-armhf-netinst\.iso' | head -1)
        if [[ -n "$base_filename" ]]; then
            echo "Descargando $base_filename"
            if wget -c --quiet --show-progress "${base_url_iso}${base_filename}"; then
                echo "Descarga completada exitosamente"
            else
                echo "Error: No se pudo descargar la versión más reciente"
            fi
        else
            echo "Error: No se pudo encontrar la versión más reciente"
        fi
    fi
fi

# Crear imagen de 10GB si no existe
if [[ ! -f "Debian-armhf.img" ]]; then
    echo "Creando imagen de disco de 10GB..."
    qemu-img create -f raw "Debian-armhf.img" 10G || {
        echo "Error creando la imagen de disco"
        exit 1
    }
    echo "Imagen creada exitosamente"
else
    echo "La imagen Debian-armhf.img ya existe"
fi

# Parámetros comunes
common_params=(
    -machine virt
    -cpu cortex-a15
    -smp 4
    -m 2048
    -drive file="Debian-armhf.img",format=raw,if=none,id=disk
    -device virtio-blk-device,drive=disk
    -netdev user,id=net0,hostfwd=tcp::5555-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::3306-:3306,hostfwd=tcp::5900-:5900,hostfwd=tcp::3389-:3389,dns=8.8.8.8,dnssearch=local
    -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56
    -accel tcg,tb-size=512,thread=multi
    -device virtio-rng-pci
    -device usb-ehci
    -device usb-tablet
    -nographic
)

# Verificar si ya existe un kernel instalado
if [[ -f "./vmlinuz-6."* && -f "./initrd.img-6."* ]]; then
    echo "Iniciando máquina virtual instalada..."
    # Buscar el kernel y initrd más recientes
    kernel_file=$(ls ./vmlinuz-6.* | sort -V | tail -1)
    initrd_file=$(ls ./initrd.img-6.* | sort -V | tail -1)
    
    # Extraer UUID del kernel o usar valor por defecto
    uuid="UUID=tu-uuid-aqui"  # Reemplazar después de la instalación
    
    qemu-system-arm "${common_params[@]}" \
        -kernel "$kernel_file" \
        -initrd "$initrd_file" \
        -append "root=$uuid console=ttyAMA0"

else
    echo "Iniciando instalación..."
    
    # Parámetros específicos de instalación
    install_params=(
        -machine type=virt,highmem=on
        -kernel "./vmlinuz"
        -initrd "./initrd.gz"
        -append "console=ttyAMA0"
        -blockdev driver=file,filename="${base_filename}",node-name=cdrom,read-only=on
        -blockdev driver=raw,file=cdrom,node-name=cdrom-raw
        -device virtio-scsi-device,id=scsi
        -device scsi-cd,drive=cdrom-raw,bus=scsi.0
        -chardev stdio,id=console,signal=off
        -serial chardev:console
        -monitor unix:./qemu-monitor.sock,server,nowait
    )
    
    qemu-system-arm "${common_params[@]}" "${install_params[@]}"
fi

echo "Proceso completado"
