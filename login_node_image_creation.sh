#!/bin/bash
set -e

echo "=== Login Image Setup ==="

# Install system packages (NO nfs-kernel-server, just nfs-common)
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

# Create slurm user with UID 981
sudo groupadd -g 981 slurm
sudo useradd -u 981 -g slurm -d /var/lib/slurm -s /bin/bash slurm

# Verify
id slurm

# Install Slurm client only
sudo apt install -y slurm-client

# Verify UID didn't change
id slurm

# CREATE SYMLINKS for Slurm client binaries (CRITICAL!)
echo "Creating symlinks in /usr/local/bin..."
sudo mkdir -p /usr/local/bin /usr/local/sbin

# Link all slurm client binaries
for bin in /usr/bin/s*; do
  if [[ $(basename "$bin") == s* ]] && [[ -f "$bin" ]]; then
    sudo ln -sf "$bin" "/usr/local/bin/$(basename $bin)"
  fi
done

# Verify critical client tools
echo "Verifying symlinks:"
ls -la /usr/local/bin/sinfo
ls -la /usr/local/bin/squeue
ls -la /usr/local/bin/sbatch
ls -la /usr/local/bin/scontrol

# Copy plugins
sudo mkdir -p /usr/local/lib64/slurm
sudo cp -r /usr/lib/x86_64-linux-gnu/slurm-wlm/* /usr/local/lib64/slurm/

# Remove /etc/slurm
sudo rm -rf /etc/slurm

# Create directories
sudo mkdir -p /usr/local/etc/slurm /var/spool/slurm /var/log/slurm /tmp/slurm_resume_data /slurm/scripts
sudo chown slurm:slurm /usr/local/etc/slurm /var/spool/slurm /var/log/slurm /tmp/slurm_resume_data /slurm/scripts
sudo chmod 755 /usr/local/etc/slurm /var/spool/slurm /var/log/slurm /tmp/slurm_resume_data /slurm/scripts

# Create dummy timer
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

# Create dummy sackd service
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

echo "Installing Python dependencies..."

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
  prometheus-client  \
  mpi4py \
  numpy \
  scipy \
  pandas \
  matplotlib \
  h5py \
  netCDF4 \
  jupyter \
  ipython


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
# OpenMPI (Development - headers included)
# ========================================
echo "Installing OpenMPI development packages..."
sudo apt install -y \
  openmpi-bin \
  libopenmpi-dev \
  openmpi-common

# ========================================
# LINEAR ALGEBRA (Development headers)
# ========================================
echo "Installing linear algebra development libraries..."
sudo apt install -y \
  libblas-dev \
  liblapack-dev \
  libopenblas-dev \
  libatlas-base-dev

# ========================================
# SCIENTIFIC LIBRARIES (Development)
# ========================================
echo "Installing scientific development libraries..."
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
echo "Installing development and debugging tools..."
sudo apt install -y \
  gdb \
  valgrind \
  strace \
  htop \
  tmux \
  screen 

# ========================================
# INTEL oneAPI (FULL DEVELOPMENT SUITE)
# ========================================
echo "Installing Intel oneAPI..."

# Add Intel repository
wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
  gpg --dearmor | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" | \
  sudo tee /etc/apt/sources.list.d/oneAPI.list

sudo apt update

# Install Intel oneAPI components (SAME AS COMPUTE)
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
  intel-oneapi-compiler-fortran \
  libpmi2-0t64

# ========================================
# ENVIRONMENT SETUP - Intel as DEFAULT
# ========================================
echo "Setting up Intel oneAPI environment..."

sudo tee /etc/profile.d/00-intel-oneapi.sh > /dev/null <<'EOF'
# Intel oneAPI environment (DEFAULT)
if [ -f /opt/intel/oneapi/setvars.sh ]; then
    source /opt/intel/oneapi/setvars.sh --force > /dev/null 2>&1
fi
export MPI_VENDOR=intel
EOF

# Create OpenMPI switcher
sudo tee /usr/local/bin/use-openmpi > /dev/null <<'EOF'
#!/bin/bash
# Switch to OpenMPI
export PATH=$(echo $PATH | tr ':' '\n' | grep -v intel | tr '\n' ':')
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v intel | tr '\n' ':')
export PATH=/usr/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
export MPI_VENDOR=openmpi
echo "Switched to OpenMPI"
which mpirun
EOF

sudo chmod +x /usr/local/bin/use-openmpi

# Source for image build
source /opt/intel/oneapi/setvars.sh --force


# ========================================
# VERIFICATION
# ========================================
echo ""
echo "=== VERIFICATION ==="
echo ""

echo "Slurm UID:"
id slurm
echo ""

echo "Compilers:"
gcc --version | head -1
g++ --version | head -1
gfortran --version | head -1
echo ""

echo "MPI (Intel - default):"
which mpicc || echo "Available after oneAPI load"
echo ""

echo "MPI (OpenMPI - fallback):"
/usr/bin/mpicc --version | head -1
echo ""

echo "Build tools:"
which cmake
which git
echo ""

echo "Editors:"
which vim
which nano
echo ""

echo "Python:"
python3 --version
python3 -c "import mpi4py; print('mpi4py: OK')"
python3 -c "import numpy; print('numpy: OK')"
echo ""

echo "Development libraries:"
pkg-config --modversion hdf5 2>/dev/null || echo "HDF5: installed"
pkg-config --libs openmpi 2>/dev/null | head -c 50 && echo "..."
echo ""

echo "✅ Login Node Development Environment Complete!"
echo ""
echo "NOTES:"
echo "  - Intel MPI is DEFAULT for compilation"
echo "  - All development headers (-dev packages) installed"
echo "  - Git, editors, build tools available"
echo "  - Same libraries as compute nodes"