

# HPC on Google cloud.

Setup a 4-node 2vCPU/node HPC system on google cloud using their HPC tool kit.  You can use the toolkit recipes below to create your own cluster.


## About the system

Our HPC system has 
- 4 compute nodes with each having two vCPU. We use C3-Highmem-4 (in google parlance) which has Intel Sapphire Rapids.
- 1 Slurm controller node
- 1 login node

All compute nodes run ubuntu 24.04 LTS and support intel onemkl libraries.

## Deployment guide

- Install the HPC toolkit from google

- Create the virtual machine images for the login, controller and compute nodes (see next section)

- (Optional) if you are destroying the old deployment (or parts there of) you need to run: ```terraform -chdir=primary destroy```. Follow this up with ```./cleanup.sh``` to remove all resources allocated to your old  machine.
- To recreate on a specific module, destroy only the specific module:
  - for controller noe: ```terraform -chdir=primary -target=module.slurm_controller```
  - for login node: ```terraform -chdir=primary -target=module.slurm_login```
  - for compute nodes: ```terraform -chdir=primary -target=module.compute_nodeset```
-Execute from the directory containing the .yaml file

`gcluster create mpplab-gcloud-hpc.yaml`

It creates the sub-directory with same as as the value of *deployment_name* in your yaml file. 

```bash
cd mpplab-c3-4vcpu-4node-1024gb-storage
terraform -chdir=primary init
terraform -chdir=primary apply
```

The last command needs you to type *yes* to complete

Alternatively, you can

```gcluster deploy mpplab-c3-4vcpu-4node-1024gb-storage```

- When only the compute node's binary or startup script is changed, you can speed up the redeployment by creating a new instance-template (copy from existing one - see below to do this via console) and then save it - say template-name-vx. You can then edit the instance-template name to this in controller's /slurm/scripts/config.yaml
  
## Creating VMs for controller node

### Step 1: Create VM and run installation script

```bash
gcloud compute instances create temp-controller-builder \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --machine-type=e2-medium \
  --boot-disk-size=50GB \
  --zone=asia-south1-b \
  --project=mpplab-482405

sleep 100

cat controller_node_image_creation.sh | gcloud compute ssh temp-controller-builder --zone=asia-south1-b --project=mpplab-482405 --command="sudo bash"
```

### Step 2: Create the image

```bash
gcloud compute instances stop temp-controller-builder --zone=asia-south1-b --project=mpplab-482405

gcloud compute images create ubuntu-2404-slurm-controller-v8 \
  --source-disk=temp-controller-builder \
  --source-disk-zone=asia-south1-b \
  --project=mpplab-482405 \
  --family=ubuntu-2404-slurm-controller

gcloud compute instances delete temp-controller-builder --zone=asia-south1-b --project=mpplab-482405 --quiet
```
### Step 3: Updating the Yaml

In the slurm_controller section, add/update name: with image name
```yaml
    instance_image:
        name: ubuntu-2404-slurm-controller-v8
        project: mpplab-482405

## Creating VMs for login node

### Step 1: Create VM and run installation script
```bash
gcloud compute instances create temp-login-builder \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --machine-type=c3-standard-4 \
  --boot-disk-size=50GB \
  --zone=asia-south1-b \
  --project=mpplab-482405

sleep 100

cat login_node_image_creation.sh | gcloud compute ssh temp-login-builder --zone=asia-south1-b --project=mpplab-482405 --command="sudo bash"
  ```
### Step 2: Create the image

```bash
gcloud compute instances stop temp-login-builder --zone=asia-south1-b --project=mpplab-482405

gcloud compute images create ubuntu-2404-slurm-login-v4 \
  --source-disk=temp-login-builder \
  --source-disk-zone=asia-south1-b \
  --project=mpplab-482405 \
  --family=ubuntu-2404-slurm-login

gcloud compute instances delete temp-login-builder --zone=asia-south1-b --project=mpplab-482405 --quiet
```

### Step 3: Updating the Yaml

In the slurm_controller section, add/update name: with image name
```yaml
    instance_image:
        name: ubuntu-2404-slurm-login-v4
        project: mpplab-482405
```
## Creating VMs for compute nodes

### Step 1: Create Base VM
On your local machine:

```bash
gcloud compute instances create temp-image-builder \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --machine-type=c4-standard-4 \
  --boot-disk-size=50GB \
  --zone=asia-south1-b \
  --project=mpplab-482405

sleep 100

cat compute_node_image_creation.sh | gcloud compute ssh temp-image-builder --zone=asia-south1-b --project=mpplab-482405 --command="sudo bash"
```

### Step 2: Create the VM Image

On the local machine

```bash
# Stop VM
gcloud compute instances stop temp-image-builder \
  --zone=asia-south1-b \
  --project=mpplab-482405

# Create image
gcloud compute images create ubuntu-2404-slurm-ready-v20 \
  --source-disk=temp-image-builder \
  --source-disk-zone=asia-south1-b \
  --project=mpplab-482405 \
  --family=ubuntu-2404-slurm

# Delete temp VM
gcloud compute instances delete temp-image-builder \
  --zone=asia-south1-b \
  --project=mpplab-482405 \
  --quiet
```

### Step 3: Updating the Yaml

In the compute_nodeset section, add/update name: with image name
```yaml
    instance_image:
        name: ubuntu-2404-slurm-ready-v18
        project: mpplab-482405
```

# Caveats

Unfortunately, the cluster doesnt up properly - more specifically the login and compute nodes's slurm is not properly configured.

## For completing the slurm config of the login node:

Run these commands on the local machine
```
#!/bin/bash
set -e

echo "========================================="
echo "mounting filestore:/nfsshare on /home"
echo "========================================="


PROJECT=mpplab-482405
ZONE=asia-south1-b
CONTROLLER=$(gcloud compute instances list --project=$PROJECT --format="value(name)" | grep controller)
LOGIN=$(gcloud compute instances list --project=$PROJECT --format="value(name)" | grep login)

TEMP=$(gcloud compute ssh $CONTROLLER --zone=$ZONE --project=$PROJECT --command="sudo cat /etc/fstab" | grep nfsshare)

gcloud compute ssh $LOGIN --zone=$ZONE --project=$PROJECT --tunnel-through-iap --command="
sudo mkdir -p /home
sudo echo $TEMP | sudo tee -a /etc/fstab
sudo mount -a
" 
echo "========================================="
echo "Fixing Munge Authentication"
echo "========================================="


echo "Prepare key on controller"
gcloud compute ssh $CONTROLLER --zone=$ZONE --project=$PROJECT --tunnel-through-iap --command="
  sudo cp /etc/munge/munge.key /tmp/munge.key
  sudo chmod 644 /tmp/munge.key
"

echo "Download from controller"
gcloud compute scp $CONTROLLER:/tmp/munge.key /tmp/munge-master.key \
  --zone=$ZONE --project=$PROJECT

echo "Upload to login node"
gcloud compute scp /tmp/munge-master.key $LOGIN:/tmp/munge.key \
  --zone=$ZONE --project=$PROJECT

echo ""
echo "Install Key on Login ==="
gcloud compute ssh $LOGIN --zone=$ZONE --project=$PROJECT --tunnel-through-iap --command="
  # Stop munge
  sudo systemctl stop munge
  sudo cp /tmp/munge.key /etc/munge/munge.key
  sudo chown munge:munge /etc/munge/munge.key
  sudo chmod 400 /etc/munge/munge.key
  
  # Verify permissions
  sudo ls -la /etc/munge/munge.key
  
  # Clear munge cache/locks
  sudo rm -rf /var/lib/munge/* 2>/dev/null || true
  sudo rm -f /var/run/munge/* 2>/dev/null || true
  
  # Start munge
  sudo systemctl enable munge
  sudo systemctl start munge
  sleep 2
  
  # Verify munge is running
  sudo systemctl status munge --no-pager | grep -E 'Active:|Loaded:'
  
  sudo systemctl daemon-reload

  echo 'Local munge test:'
  munge -n | unmunge | grep -E 'STATUS|ENCODE_HOST|DECODE_HOST'
  
  # Clean up
  rm /tmp/munge.key
"

# Clean up controller
gcloud compute ssh $CONTROLLER --zone=$ZONE --project=$PROJECT --command="
  rm /tmp/munge.key
"

# Clean up local
rm /tmp/munge-master.key

echo ""
echo "========================================="
echo "✅ Munge Fix Complete!"
echo "========================================="



#copy controller:/slurm/scripts/{conf.py,config.yaml} and controller:/usr/local/etc/slurm/{slurm.conf,cloud.conf} to login 

echo "copying conf.py and config.yaml from controller to local /tmp"
gcloud compute ssh $CONTROLLER --zone=$ZONE --project=$PROJECT --tunnel-through-iap --command="
sudo cp /slurm/scripts/conf.py /tmp/conf.py
sudo cp /slurm/scripts/config.yaml /tmp/config.yaml
sudo chmod 644 /tmp/conf.py  /tmp/config.yaml
"
gcloud compute scp $CONTROLLER:/tmp/conf.py /tmp --zone=$ZONE --tunnel-through-iap --project=$PROJECT
gcloud compute scp $CONTROLLER:/tmp/config.yaml /tmp --zone=$ZONE --tunnel-through-iap --project=$PROJECT
#
echo" Upload conf.py and config.yaml to login"
gcloud compute scp /tmp/conf.py $LOGIN:/tmp/conf.py --zone=$ZONE --project=$PROJECT --tunnel-through-iap
gcloud compute scp /tmp/config.yaml $LOGIN:/tmp/config.yaml --zone=$ZONE --project=$PROJECT --tunnel-through-iap

echo "copying slurm.conf and cloud.conf from controller to local /tmp"
gcloud compute scp $CONTROLLER:/usr/local/etc/slurm/cloud.conf /tmp --zone=$ZONE --project=$PROJECT --tunnel-through-iap
gcloud compute scp $CONTROLLER:/usr/local/etc/slurm/slurm.conf /tmp --zone=$ZONE --project=$PROJECT --tunnel-through-iap
echo "copying slurm.conf and cloud.conf from local /tmp to login node"
gcloud compute scp /tmp/slurm.conf $LOGIN:/tmp --zone=$ZONE --project=$PROJECT --tunnel-through-iap
gcloud compute scp /tmp/cloud.conf $LOGIN:/tmp --zone=$ZONE --project=$PROJECT --tunnel-through-iap

echo "Moving conf.py, config.yaml, slurm.conf, cloud.conf right directorie sin login node"
gcloud compute ssh $LOGIN --zone=$ZONE --project=$PROJECT --tunnel-through-iap --command="
sudo mv /tmp/conf.py /slurm/scripts/conf.py
sudo mv /tmp/config.yaml /slurm/scripts/config.yaml
sudo chown slurm:slurm /slurm/scripts/conf.py /slurm/scripts/config.yaml
sudo mkdir -p /usr/local/etc/slurm
sudo mv /tmp/slurm.conf /usr/local/etc/slurm 
sudo mv /tmp/cloud.conf /usr/local/etc/slurm 
sudo chown -R slurm:slurm /usr/local/etc/slurm
sudo ln -s /usr/local/etc/slurm /etc/slurm
"
```

## For completing the slurm config on the compute nodes

### First we need to export a couple of directories from the controller 
On the controller:
Add or modify /etc/exports to have :
 Slurm configuration directory (read-only for login/compute nodes)
/usr/local/etc/slurm 10.0.0.0/8(ro,sync,no_subtree_check,no_root_squash)
/slurm 10.0.0.0/8(ro,sync,no_subtree_check,no_root_squash)

Followed by 
```
sudo exportfs -ra

# Verify it's applied
sudo exportfs -v | grep slurm
```
## Updating the instance_template file
Need to add the following to the startup_script to allow setting of the controller compatible munge key to enable slurm communication. Unfortunately, putting this script in the blueprint's id:settings:startup_script doesnt work as the code snippet there is appended to google's startup script - hence errors happen before reaching this portion.

Hence the way we have found is to go to the console/compute-engine/instance-templates and make copy a computenode template (create similar button on top when you select a template to be copie. ). Then scroll down to click advanced and management and within that there is a window which has loaded google's startup script. You can make additions here and save to a new template. 

# Useful commands for system administration

On the local machine

'''
PROJECT=mpplab-482405
ZONE=asia-south1-b
CONTROLLER=$(gcloud compute instances list --project=$PROJECT --format="value(name)" | grep controller)
LOGIN=$(gcloud compute instances list --project=$PROJECT --format="value(name)" | grep login)
'''

-ssh into the login node

```gcloud compute ssh $LOGIN --zone=$ZONE --project=$PROJECT --tunnel-through-iap```

-ssh into the controller node

```
gcloud compute ssh $CONTROLLER --zone=$ZONE --project=$PROJECT --tunnel-through-iap
```

When creating a new machine image for the compute node, 
you need to update the /slurm/scripts/config.yaml on the controller

get the instance name using:
```
gcloud compute instance-templates list --project=mpplab-482405
```
Update the instance_template parameter in config.yaml

```
sudo systemctl restart slurmctld
sudo systemctl daemon-reload
sudo journalctl -u slurmctld -n 50
```

Powering up compute nodes:
```
sudo scontrol update nodename=mpplabc34n-computenodeset-[0-3] state=power_up
```
