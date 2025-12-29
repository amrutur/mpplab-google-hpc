#!/bin/bash
PROJECT="mpplab-482405"
PATTERN="mpplab"

echo "=== Cleaning up all resources for project $PROJECT matching pattern $PATTERN ==="

# Function to delete resources
delete_resources() {
  local resource_type=$1
  local list_cmd=$2
  local delete_cmd=$3
  
  echo "Deleting ${resource_type}..."
  eval $list_cmd | while read line; do
    if [ ! -z "$line" ]; then
      echo "  Deleting: $line"
      eval $delete_cmd "$line"
    fi
  done
}

# Delete instances first
gcloud compute instances list --project=$PROJECT --format="value(name,zone)" | grep $PATTERN | \
while read name zone; do
  gcloud compute instances delete $name --zone=$zone --project=$PROJECT --quiet
done

# Delete addresses
gcloud compute addresses list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read name region; do
  gcloud compute addresses delete $name --region=$region --project=$PROJECT --quiet
done

# Delete buckets  
gsutil ls -p $PROJECT | grep $PATTERN | while read bucket; do
  gsutil -m rm -r $bucket
done

# Delete disks
gcloud compute disks list --project=$PROJECT --format="value(name,zone)" | grep $PATTERN | \
while read name zone; do
  gcloud compute disks delete $name --zone=$zone --project=$PROJECT --quiet
done

# Delete routers
gcloud compute routers list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read name region; do
  gcloud compute routers delete $name --region=$region --project=$PROJECT --quiet
done

# Delete firewall rules
gcloud compute firewall-rules list --project=$PROJECT --format="value(name)" | grep $PATTERN | \
while read rule; do
  gcloud compute firewall-rules delete $rule --project=$PROJECT --quiet
done

# Delete subnets
gcloud compute networks subnets list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read subnet region; do
  gcloud compute networks subnets delete $subnet --region=$region --project=$PROJECT --quiet
done

# Delete network
gcloud compute networks list --project=$PROJECT --format="value(name)" | grep $PATTERN | \
while read network; do
  gcloud compute networks delete $network --project=$PROJECT --quiet
done

# Delete filestore
gcloud filestore instances list --project=$PROJECT --format="value(name,location)" | grep $PATTERN | \
while read name location; do
  gcloud filestore instances delete $name --location=$location --project=$PROJECT --quiet
done

echo "=== Cleanup complete! ==="
