#!/bin/bash
# User data script for GPU compute nodes
# This runs when each new instance starts up

set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting GPU node initialization at $(date)"

# Update system
apt-get update -y

# Install basic dependencies
apt-get install -y \
    curl \
    wget \
    gnupg \
    software-properties-common \
    build-essential \
    dkms

# Install NVIDIA drivers and CUDA toolkit
# Note: Adjust version based on your needs
echo "Installing NVIDIA drivers and CUDA..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-keyring_1.0-1_all.deb
dpkg -i cuda-keyring_1.0-1_all.deb
apt-get update
apt-get install -y cuda-toolkit-11-8

# Install Slurm and Munge
echo "Installing Slurm and Munge..."
apt-get install -y slurm-wlm munge

# Configure Munge
# Note: You'll need to copy your munge.key from the head node
systemctl enable munge
systemctl start munge

# Configure Slurm
# Note: You'll need to customize slurm.conf for your cluster
# This is a minimal example - replace with your actual configuration
cat > /etc/slurm-llnl/slurm.conf << 'EOF'
# REPLACE THIS WITH YOUR ACTUAL SLURM CONFIGURATION
ClusterName=hpc-cluster
ControlMachine=slurm-head
AuthType=auth/munge
CryptoType=crypto/munge
MpiDefault=none
ProctrackType=proctrack/cgroup
ReturnToService=1
SlurmctldPidFile=/var/run/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
StateSaveLocation=/var/spool/slurmctld
SwitchType=switch/none
TaskPlugin=task/affinity

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core

# LOGGING
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm-llnl/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm-llnl/slurmd.log

# NODES (this will be dynamically updated)
NodeName=gpu-node-[001-100] CPUs=4 RealMemory=15000 Gres=gpu:1 State=UNKNOWN
PartitionName=gpu Nodes=gpu-node-[001-100] Default=YES MaxTime=INFINITE State=UP
EOF

# Create slurm user and directories
useradd -r -s /bin/false slurm || true
mkdir -p /var/spool/slurmd /var/log/slurm-llnl
chown slurm:slurm /var/spool/slurmd /var/log/slurm-llnl

# Configure GPU resources for Slurm
cat > /etc/slurm-llnl/gres.conf << 'EOF'
AutoDetect=nvml
EOF

# Enable and start slurmd (not slurmctld - this is a compute node)
systemctl enable slurmd
systemctl start slurmd

# Install monitoring tools
echo "Installing monitoring tools..."
apt-get install -y prometheus-node-exporter

# Enable and start node exporter
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Signal that the node is ready
echo "GPU node initialization completed at $(date)"

# Optional: Send a signal to the head node that this node is ready
# You can implement a webhook or API call here if needed
