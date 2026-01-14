#!/bin/bash
set -e  # Exit on any error

echo "=== Compute Image  Setup - HPC Ready ==="


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
  libjwt-dev 

# ========================================
# COMPILERS & BUILD TOOLS
# ========================================
echo "Installing compilers and build tools..."
sudo apt install -y \
  build-essential \
  gfortran \
  cmake \
  git \
  pkg-config \
  autoconf \
  automake \
  libtool

# ========================================
# OpenMPI (Install but DON'T prioritize)
# ========================================
echo "Installing OpenMPI (as fallback)..."
sudo apt install -y \
  openmpi-bin \
  libopenmpi-dev \
  openmpi-common

# Verify OpenMPI is available
/usr/bin/mpirun --version


# ========================================
# LINEAR ALGEBRA
# ========================================
echo "Installing linear algebra libraries..."
sudo apt install -y \
  libblas-dev \
  liblapack-dev \
  libopenblas-dev \
  libatlas-base-dev

# ========================================
# SCIENTIFIC LIBRARIES
# ========================================
echo "Installing scientific libraries..."
sudo apt install -y \
  libfftw3-dev \
  libfftw3-mpi-dev \
  libhdf5-dev \
  libhdf5-mpi-dev \
  libnetcdf-dev \
  libnetcdf-mpi-dev \
  libgsl-dev \
  libboost-all-dev

# ========================================
# DEBUGGING & PERFORMANCE TOOLS
# ========================================
echo "Installing debugging and performance tools..."
sudo apt install -y \
  gdb \
  valgrind \
  strace

# ========================================
# INTEL oneAPI (Sapphire Rapids optimized)
# ========================================
echo "Installing Intel oneAPI..."

# Add Intel repository
wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | sudo tee /etc/apt/sources.list.d/oneAPI.list
sudo apt update

# Install Intel oneAPI components
sudo apt install -y \
  intel-oneapi-mkl \
  intel-oneapi-mkl-devel \
  intel-oneapi-ipp \
  intel-oneapi-ipp-devel \
  intel-oneapi-tbb \
  intel-oneapi-tbb-devel \
  intel-oneapi-dnnl \
  intel-oneapi-dnnl-devel \
  intel-oneapi-mpi \
  intel-oneapi-mpi-devel \
  intel-oneapi-compiler-dpcpp-cpp \
  intel-oneapi-compiler-fortran\
  libpmi2-0t64 


# ========================================
# ENVIRONMENT SETUP - Intel MPI as DEFAULT
# ========================================
echo "Setting up Intel oneAPI environment..."

# Create environment file that loads Intel by DEFAULT
sudo tee /etc/profile.d/00-intel-oneapi.sh > /dev/null <<'EOF'
# Intel oneAPI environment (PRIORITY - loads first)
# This makes Intel MPI, MKL, etc. the default

if [ -f /opt/intel/oneapi/setvars.sh ]; then
    # Suppress warnings during source
    source /opt/intel/oneapi/setvars.sh --force > /dev/null 2>&1
fi

# Export for clarity
export MPI_VENDOR=intel
EOF

# Create OpenMPI environment (FALLBACK - only if explicitly sourced)
sudo tee /etc/profile.d/99-openmpi-fallback.sh > /dev/null <<'EOF'
# OpenMPI fallback environment
# To use OpenMPI instead of Intel MPI, run:
#   source /etc/profile.d/use-openmpi.sh

# DO NOT auto-load - only when explicitly requested
EOF

# Create script to switch to OpenMPI if needed
sudo tee /usr/local/bin/use-openmpi > /dev/null <<'EOF'
#!/bin/bash
# Switch to OpenMPI (removes Intel from PATH)

# Remove Intel paths
export PATH=$(echo $PATH | tr ':' '\n' | grep -v intel | tr '\n' ':')
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v intel | tr '\n' ':')

# Add OpenMPI paths
export PATH=/usr/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
export MPI_VENDOR=openmpi

echo "Switched to OpenMPI"
which mpirun
mpirun --version
EOF

sudo chmod +x /usr/local/bin/use-openmpi

# Source Intel environment for image build
source /opt/intel/oneapi/setvars.sh --force



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

echo "=== Step 7: Create target and other directories ==="
sudo mkdir -p /usr/local/etc/slurm
sudo mkdir -p /var/spool/slurm
sudo mkdir -p /var/log/slurm
sudo mkdir -p /tmp/slurm_resume_data
sudo mkdir -p /slurm/scripts

sudo chown slurm:slurm /usr/local/etc/slurm /var/spool/slurm /var/log/slurm /tmp/slurm_resume_data /slurm/scripts

sudo chmod 755 /usr/local/etc/slurm /var/spool/slurm /var/log/slurm /tmp/slurm_resume_data /slurm/scripts

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

[Service]--boot-disk-size=50GB \
Type=oneshot
ExecStart=/bin/true

[Install]
WantedBy=multi-user.target
EOF

echo "Setting up Slurm config fallback mechanism..."

# Smart fallback script
sudo tee /usr/local/bin/fix-slurm-configs.sh > /dev/null <<'EOF'
#!/bin/bash
set -e

# Exit silently if configs already exist
if [ -f /etc/slurm/slurm.conf ] && [ -f /etc/slurm/cloud.conf ]; then
  exit 0
fi

logger "Slurm configs missing - attempting fallback NFS mount from controller"

# Resolve controller
CONTROLLER_IP=$(getent hosts mpplabc34n-controller 2>/dev/null | awk '{print $1}')
if [ -z "$CONTROLLER_IP" ]; then
  logger "ERROR: Cannot resolve controller hostname"
  exit 1
fi

# Mount controller's configs via NFS
mkdir -p /usr/local/etc/slurm
if ! mount | grep -q "/usr/local/etc/slurm"; then
  mount -t nfs -o ro,hard,intr ${CONTROLLER_IP}:/usr/local/etc/slurm /usr/local/etc/slurm || {
    logger "ERROR: Failed to NFS mount slurm configs"
    exit 1
  }
fi

# Create symlink
ln -sf /usr/local/etc/slurm /etc/slurm

logger "Slurm configs successfully mounted from controller"
exit 0
EOF

sudo chmod +x /usr/local/bin/fix-slurm-configs.sh

# Override slurmd to run fallback first
sudo mkdir -p /etc/systemd/system/slurmd.service.d
sudo tee /etc/systemd/system/slurmd.service.d/config-fallback.conf > /dev/null <<'EOF'
[Service]
# Try to get configs from controller if missing
ExecStartPre=/usr/local/bin/fix-slurm-configs.sh

# Restart a few times if fails (configs might not be ready immediately)
Restart=on-failure
RestartSec=15s
StartLimitBurst=5
StartLimitIntervalSec=300
EOF

sudo systemctl daemon-reload

echo "✅ Slurm config fallback mechanism installed"

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
  prometheus-client \
  mpi4py \
  numpy \
  scipy \
  pandas \
  matplotlib \
  h5py \
  netCDF4

echo "Disabling slurmd to prevent premature startup"
systemctl disable slurmd
DISABLE_EXIT=$?
echo "Disable exit code: $DISABLE_EXIT"

# Verify the state
systemctl is-enabled slurmd && echo "ERROR: Still enabled!" || echo "SUCCESS: Disabled"


echo "=== Step 10: Verification ==="

echo "Slurm user ID:"
id slurm

echo "Python modules:"
python3 -c "from google.cloud import tpu_v2; print('google-cloud-tpu: OK')"
python3 -c "import yaml; print('pyyaml: OK')"
python3 -c "import addict; print('addict: OK')"
python3 -c "import mpi4py; print('mpi4py: OK')"
python3 -c "import numpy; print('numpy: OK')"

echo "NFS support:"
which mount.nfs && echo "NFS: OK"

echo "Plugins:"
ls /usr/local/lib64/slurm/*.so | wc -l
echo "plugin files found"

echo "Timer files:"
ls -la /etc/systemd/system/slurmcmd.*

echo "Compilers:"
gcc --version | head -1
g++ --version | head -1
gfortran --version | head -1
icc --version 2>/dev/null | head -1 || echo "Intel C compiler: Available after oneAPI load"
ifort --version 2>/dev/null | head -1 || echo "Intel Fortran: Available after oneAPI load"
echo ""

echo "MPI (DEFAULT - Intel MPI):"
which mpirun
mpirun --version | head -1
echo ""

echo "MPI (FALLBACK - OpenMPI):"
/usr/bin/mpirun --version | head -1
echo ""

echo "Intel Libraries:"
echo "MKL_ROOT: ${MKLROOT:-Not loaded yet (available after boot)}"
echo "I_MPI_ROOT: ${I_MPI_ROOT:-Not loaded yet (available after boot)}"
echo ""

echo "✅ Intel oneAPI + OpenMPI Compute Image Complete!"
echo ""
echo "NOTES:"
echo "  - Intel MPI is DEFAULT (in PATH first)"
echo "  - To use OpenMPI: run 'source /usr/local/bin/use-openmpi'"
echo "  - Intel libs available after sourcing /etc/profile.d/00-intel-oneapi.sh"


exit
