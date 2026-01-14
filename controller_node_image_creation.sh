#!/bin/bash
set -e

echo "=== Controller Image v6 Setup ==="

# Install system packages
sudo apt update
sudo apt install -y \
  unzip \
  python3-pip \
  build-essential \
  nfs-kernel-server \
  munge \
  libmunge-dev \
  libmunge2 \
  libhwloc-dev \
  libdbus-1-dev \
  liblua5.3-dev \
  libreadline-dev \
  libpam0g-dev \
  libssl-dev \
  libjson-c-dev \
  libhttp-parser-dev \
  libyaml-dev \
  libjwt-dev \
  autoconf \
  automake \
  libtool \
  pkg-config \
  mariadb-server \
  libmariadb-dev

# Create slurm user with UID 981 FIRST
sudo groupadd -g 981 slurm
sudo useradd -u 981 -g slurm -d /var/lib/slurm -s /bin/bash slurm

echo "Slurm user created:"
id slurm

# Install ALL Slurm packages
sudo apt install -y slurmctld slurmdbd slurmrestd slurmd slurm-client

echo "Verify UID after package install:"
id slurm

# FIX slurmrestd service to run as slurm user
echo "Fixing slurmrestd service..."
sudo mkdir -p /etc/systemd/system/slurmrestd.service.d
sudo tee /etc/systemd/system/slurmrestd.service.d/override.conf > /dev/null <<'EOF'
[Service]
User=slurm
Group=slurm
RuntimeDirectory=slurmrestd
RuntimeDirectoryMode=0755
# Override socket path to be inside RuntimeDirectory
ExecStart=
ExecStart=/usr/sbin/slurmrestd -vvv unix:/run/slurmrestd/slurmrestd.socket
EOF

sudo systemctl daemon-reload

# CREATE SYMLINKS for all Slurm binaries
echo "Creating symlinks in /usr/local/bin..."
sudo mkdir -p /usr/local/bin /usr/local/sbin

# Link all slurm binaries from /usr/bin
for bin in /usr/bin/s*; do
  if [[ $(basename "$bin") == s* ]] && [[ -f "$bin" ]]; then
    sudo ln -sf "$bin" "/usr/local/bin/$(basename $bin)"
  fi
done

# Link sbin binaries
for bin in /usr/sbin/slurm*; do
  if [[ -f "$bin" ]]; then
    sudo ln -sf "$bin" "/usr/local/sbin/$(basename $bin)"
  fi
done

# Verify critical binaries
echo "Verifying symlinks:"
ls -la /usr/local/bin/sacctmgr
ls -la /usr/local/sbin/slurmctld
ls -la /usr/local/sbin/slurmdbd
ls -la /usr/local/sbin/slurmrestd

# Copy plugins
sudo mkdir -p /usr/local/lib64/slurm
sudo cp -r /usr/lib/x86_64-linux-gnu/slurm-wlm/* /usr/local/lib64/slurm/

# Remove /etc/slurm
sudo rm -rf /etc/slurm

# Create directories
sudo mkdir -p /usr/local/etc/slurm /var/spool/slurm /var/log/slurm
sudo chown slurm:slurm /usr/local/etc/slurm /var/spool/slurm /var/log/slurm

# Create /tmp directory for resume script
sudo mkdir -p /tmp/slurm_resume_data
sudo chown slurm:slurm /tmp/slurm_resume_data
sudo chmod 755 /tmp/slurm_resume_data

# CREATE /slurm DIRECTORY STRUCTURE
echo "Creating /slurm directory structure..."
sudo mkdir -p /slurm/scripts
sudo chown -R slurm:slurm /slurm
sudo chmod 755 /slurm
sudo chmod 755 /slurm/scripts

# Create dummy timer files
sudo tee /etc/systemd/system/slurmcmd.timer > /dev/null <<'EOF'
[Unit]
Description=Slurm Command Timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/slurmcmd.service > /dev/null <<'EOF'
[Unit]
Description=Slurm Command Service
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF

# Dummy slurm_load_bq timer (BigQuery integration - optional)
sudo tee /etc/systemd/system/slurm_load_bq.timer > /dev/null <<'EOF'
[Unit]
Description=Slurm Load BigQuery Timer (dummy)

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

sudo tee /etc/systemd/system/slurm_load_bq.service > /dev/null <<'EOF'
[Unit]
Description=Slurm Load BigQuery Service (dummy)

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Dummy sackd service (Slurm accounting - optional)
sudo tee /etc/systemd/system/sackd.service > /dev/null <<'EOF'
[Unit]
Description=Slurm Accounting Daemon (dummy)
After=slurmdbd.service

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

# Install Python dependencies
sudo pip3 install --break-system-packages --ignore-installed \
  google-cloud-secret-manager \
  google-cloud-storage \
  google-cloud-compute \
  google-cloud-tpu \
  google-cloud-logging \
  google-cloud-monitoring \
  google-cloud-pubsub \
  google-api-python-client \
  google-auth \
  google-auth-httplib2 \
  pyyaml \
  addict \
  more-executors \
  requests \
  jinja2 \
  prometheus-client

# Pre-configure NFS exports for Slurm
echo "Configuring NFS exports..."
sudo tee /etc/exports <<'EOF'
# Slurm configuration directory (read-only for login/compute nodes)
/usr/local/etc/slurm 10.0.0.0/8(ro,sync,no_subtree_check)
/slurm 10.0.0.0/8(ro,sync,no_subtree_check)
EOF

echo "=== Verification ==="
echo "Slurm packages installed:"
dpkg -l | grep slurm | grep "^ii"
echo ""
echo "slurmrestd service override:"
cat /etc/systemd/system/slurmrestd.service.d/override.conf
echo ""
echo "Slurm UID:"
id slurm
echo ""
echo "✅ Setup complete!"