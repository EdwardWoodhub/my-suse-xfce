# 1. 继承 SUSE 官方整机不可变底座
FROM registry.suse.com/suse/sl-micro/6.2/baremetal-os-container:latest

# 2. 添加 openSUSE 官方标准仓库（包含 XFCE 与图形界面套件）
RUN zypper --non-interactive ar -cfp 90 https://download.opensuse.org/distribution/leap/16.0/repo/oss/ oss || true && \
    zypper --non-interactive ar -cfp 90 https://download.opensuse.org/distribution/leap/16.0/repo/non-oss/ non-oss || true && \
    zypper --non-interactive ar -cfp 90 https://download.opensuse.org/repositories/M17N:/fonts/16.0/ M17N-fonts || true 

# 3. 导入 GPG 密钥并安装 XFCE 桌面环境与 SDDM
# glibc-locale-base解决btop：No UTF-8 locale detected
RUN zypper --non-interactive --gpg-auto-import-keys refresh && \
    zypper --non-interactive in \
        btop \
        fastfetch \
        fontconfig \
        gedit \
        glibc-locale-base \
        htop \
        konsole \
        meld \
        open-vm-tools \
        open-vm-tools-desktop \
        patterns-xfce-xfce \
        pluma \
        python3 \
        sddm \
        syncthing \
        uv \
        wqy-microhei-fonts \
        xorg-x11-server \
        xfce4-terminal \
        xfce4-session \
        xf86-video-vmware \
        xf86-input-vmmouse \
        xfwm4 && \
    fc-cache -f && \
    zypper clean -a

# ------------------------------
# 4a. 基础用户与系统权限配置
# ------------------------------
RUN groupadd -f wheel && \
    # 创建 liveuser 默认用户
    useradd -m -G wheel -s /bin/bash liveuser && \
    echo "liveuser:liveuser" | chpasswd && \
    # 设置 root 密码及免密 sudo
    echo "root:root" | chpasswd && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ------------------------------
# 4b. 固化 sudo 安全路径
# ------------------------------
RUN echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/sudoers

# ------------------------------
# 4c. 固化 Recovery (8GB) 与 State (100GB) 分区大小
# ------------------------------
RUN mkdir -p /etc/elemental && \
    printf 'install:\n  snapshotter:\n    type: btrfs\n  partitions:\n    recovery:\n      size: 8192\n    state:\n      size: 102400\n' > /etc/elemental/config.yaml

# ------------------------------
# 4d. 直接 Patch 镜像底层所有 Elemental/GRUB 模板源文件
# ------------------------------
RUN find /usr/share /usr/lib /etc -type f \( -name "*.cfg" -o -name "*.sh" -o -name "grub_*" -o -name "*.yaml" \) 2>/dev/null | \
    xargs grep -l "default_fallback" 2>/dev/null | while read -r file; do \
        echo "Patching GRUB fallback in: $file"; \
        # 1. 匹配带引号的情况 (例如 default_fallback="0 1 2 3 4" 或单引号) 统一替换为 "0"
        sed -i -E 's/default_fallback=["'\''][0-9 ]+["'\'']/default_fallback="0"/g' "$file"; \
        # 2. 匹配完全不带引号的情况 (例如 default_fallback=0 1 2 3 4) 统一替换为 0
        sed -i -E 's/default_fallback=[0-9 ]+$/default_fallback=0/g' "$file"; \
    done || true

# ------------------------------
# 4e. 注入 Elemental 声明式 OEM 阶段钩子（双保险，拦截安装与升级写盘）
# ------------------------------
RUN mkdir -p /system/oem && \
    printf '%s\n' \
      'name: "Force GRUB Fallback to 0"' \
      'stages:' \
      '  install.after:' \
      '    - name: "Lock default_fallback to 0 after installation"' \
      '      commands:' \
      '        - sed -i "s/default_fallback=.*/default_fallback=0/" /run/elemental/efi/grub_oem_env 2>/dev/null || true' \
      '        - sed -i "s/default_fallback=.*/default_fallback=0/" /boot/efi/grub_oem_env 2>/dev/null || true' \
      '  upgrade.after:' \
      '    - name: "Lock default_fallback to 0 after upgrade"' \
      '      commands:' \
      '        - sed -i "s/default_fallback=.*/default_fallback=0/" /run/elemental/efi/grub_oem_env 2>/dev/null || true' \
      '        - sed -i "s/default_fallback=.*/default_fallback=0/" /boot/efi/grub_oem_env 2>/dev/null || true' \
      > /system/oem/00_grub_patch.yaml



# 1. 彻底屏蔽所有云边注册、自杀评估、自动重启以及网络阻断单元
RUN mkdir -p /etc/systemd/system && \
    ln -sf /dev/null /etc/systemd/system/elemental-system-agent.service && \
    ln -sf /dev/null /etc/systemd/system/elemental-boot-assessment.service && \
    ln -sf /dev/null /etc/systemd/system/elemental-boot-assessment.timer && \
    ln -sf /dev/null /etc/systemd/system/elemental-register.service && \
    ln -sf /dev/null /etc/systemd/system/elemental-register.timer && \
    ln -sf /dev/null /etc/systemd/system/rebootmgr.service && \
    ln -sf /dev/null /etc/systemd/system/NetworkManager-wait-online.service && \
    ln -sf /dev/null /etc/systemd/system/plymouth-quit-wait.service && \
    ln -sf /dev/null /etc/systemd/system/plymouth-start.service

# 2. 从源头直接卸载 plymouth（防止它打包进 initramfs 从早期阶段卡死）
RUN zypper rm -y --clean-deps plymouth plymouth-scripts || true

# 3. 固化内核引导参数（双重保险，告知内核绝不拉起开机动画）
RUN mkdir -p /etc/elemental/config.d && \
    echo 'extra_cmdline: "plymouth.enable=0"' > /etc/elemental/config.d/cmdline.yaml

# 2. 彻底掐死 systemd 内核与硬件看门狗超时（防止硬件强行重启）
RUN mkdir -p /etc/systemd/system.conf.d && \
    printf '[Manager]\nRuntimeWatchdogSec=0\nRebootWatchdogSec=0\nKExecWatchdogSec=0\n' > /etc/systemd/system.conf.d/disable-watchdogs.conf

# 3. 固化 peter 用户、免密 sudo 与全局 secure_path 环境变量
RUN useradd -m -G wheel -s /bin/bash peter && \
    echo "peter:peter" | chpasswd && \
    mkdir -p /etc/sudoers.d && \
    echo 'peter ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/peter && \
    chmod 0440 /etc/sudoers.d/peter && \
    echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/sudoers


# 5. 配置 SDDM 开机自动免密登录 liveuser 进入 XFCE
#RUN mkdir -p /etc/sddm/sddm.conf.d && \
#    printf "[Seat:*]\nautologin-user=liveuser\nautologin-user-timeout=0\nuser-session=xfce\n" > /etc/sddm/sddm.conf.d/50-autologin.conf

# 1. 显式指定 openSUSE 的默认显示管理器为 sddm
RUN mkdir -p /etc/sysconfig && \
    echo 'DISPLAYMANAGER="sddm"' > /etc/sysconfig/displaymanager

# 2. 强行建立 display-manager 和 graphical.target 软链接
RUN systemctl set-default graphical.target && \
    mkdir -p /etc/systemd/system/graphical.target.wants && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service && \
    ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/graphical.target.wants/sddm.service


# 7. 确保 vmtoolsd 服务开机自启
RUN systemctl enable vmtoolsd.service


