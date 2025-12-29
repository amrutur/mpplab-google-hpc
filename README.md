

# HPC on Google cloud.

Setup a 4-node 2vCPU/node HPC system on google cloud using their HPC tool kit.  You can use the toolkit recipes below to create your own cluster.


## About the system

The HPC system has 
- 4 compute nodes with each having two vCPU. We use C3-Highmem-4 (in google parlance)
- 1 Slurm controller node
- 1 login node

All nodes run ubuntu 24.04 LTS

## Deployment guide

Install the HPC toolkit from google

Execute from the directory containing the .yaml file

`gcluster create mpplab-gcloud-hpc.yaml`

It creates the sub-directory with same as as the value of *deployment_name* in your yaml file. 

```bash
cd mpplab-c3-4vcpu-4node-1024gb-storage
terraform -chdir=primary init
terraform -chdir=primary apply
```

The last command needs you to type *yes* to complete

## Creating VMs for compute nodes

### Step 1: Create Base VM
On your local machine:

```bash
gcloud compute instances create temp-image-builder-v14 \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --machine-type=e2-medium \
  --zone=asia-south1-b \
  --project=mpplab-482405
```

### Step 2: SSH to VM

```bash
gcloud compute ssh temp-image-builder-v14 --zone=asia-south1-b --project=mpplab-482405
```

### Step 3: Complete setup of VM

Run the contents of *compute_node_image_creation.sh* in the VM

### Step 4: Create the VM Image

On the local machine

```bash
# Stop VM
gcloud compute instances stop temp-image-builder-v14 \
  --zone=asia-south1-b \
  --project=mpplab-482405

# Create image
gcloud compute images create ubuntu-2404-slurm-ready-v14 \
  --source-disk=temp-image-builder-v14 \
  --source-disk-zone=asia-south1-b \
  --project=mpplab-482405 \
  --family=ubuntu-2404-slurm

# Verify image created
gcloud compute images describe ubuntu-2404-slurm-ready-v14 \
  --project=mpplab-482405

# Delete temp VM
gcloud compute instances delete temp-image-builder-v14 \
  --zone=asia-south1-b \
  --project=mpplab-482405 \
  --quiet
```
### Step 5: Updating the Yaml

For the compute_nodeset section, add/update these lines
```yaml
    instance_image:
        name: ubuntu-2404-slurm-ready-v14 
        project: mpplab-482405
```
