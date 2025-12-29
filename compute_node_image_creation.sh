#!/bin/bash
set -e  # Exit on any error

echo "=== Step 1: Update and install system dependencies ==="
sudo apt update
sudo apt install -y \
  unzip \
  python3-pip \
  build-essential \
  nfs-common \
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
  pkg-config

echo "=== Step 2: Create slurm user with UID 981 BEFORE installing Slurm ==="
sudo groupadd -g 981 slurm
sudo useradd -u 981 -g slurm -d /var/lib/slurm -s /bin/bash slurm

echo "Verify slurm UID:"
id slurm
# Should show: uid=981(slurm) gid=981(slurm)

echo "=== Step 3: Install Slurm packages ==="
sudo apt install -y slurmd slurmctld slurm-client

echo "=== Step 4: VERIFY UID didn't change ==="
id slurm
# MUST still be 981!

echo "=== Step 5: Copy Slurm plugins to expected location ==="
sudo mkdir -p /usr/local/lib64/slurm
sudo cp -r /usr/lib/x86_64-linux-gnu/slurm-wlm/* /usr/local/lib64/slurm/

echo "Verify plugins copied:"
ls -la /usr/local/lib64/slurm/ | head -10

echo "=== Step 6: Remove /etc/slurm (let setup.py create symlink) ==="
sudo rm -rf /etc/slurm

echo "=== Step 7: Create target directories ==="
sudo mkdir -p /usr/local/etc/slurm
sudo mkdir -p /var/spool/slurm
sudo mkdir -p /var/log/slurm
sudo chown slurm:slurm /usr/local/etc/slurm /var/spool/slurm /var/log/slurm

echo "=== Step 8: Create slurmcmd timer and service files ==="
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

sudo systemctl daemon-reload

echo "=== Step 9: Install Python dependencies ==="
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

echo "=== Step 10: Verification ==="
echo "Slurm version:"
slurmd --version

echo "Slurm user ID:"
id slurm

echo "Python modules:"
python3 -c "from google.cloud import tpu_v2; print('google-cloud-tpu: OK')"
python3 -c "import yaml; print('pyyaml: OK')"
python3 -c "import addict; print('addict: OK')"


echo "NFS support:"
which mount.nfs && echo "NFS: OK"

echo "Plugins:"
ls /usr/local/lib64/slurm/*.so | wc -l
echo "plugin files found"

echo "Timer files:"
ls -la /etc/systemd/system/slurmcmd.*

echo ""
echo "=== ✅ SETUP COMPLETE ==="
echo "Final slurm UID verification:"
id slurm
echo ""
echo "If UID is 981, everything is ready!"

exit