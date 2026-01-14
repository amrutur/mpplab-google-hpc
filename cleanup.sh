#!/bin/bash

PROJECT="mpplab-482405"
PATTERN="mpplab"

echo "=== WARNING: This will delete ALL resources matching '$PATTERN' in project $PROJECT ==="
echo "This includes: VMs, disks, networks, buckets, templates, etc."
read -p "Are you sure? (type 'yes' to proceed): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo "=== Starting cleanup... ==="

# 1. Delete instances first
echo "Deleting instances..."
gcloud compute instances list --project=$PROJECT --format="value(name,zone)" | grep $PATTERN | \
while read name zone; do
  echo "  Deleting instance: $name (zone: $zone)"
  gcloud compute instances delete $name --zone=$zone --project=$PROJECT --quiet || true
done

# Wait for instances to fully terminate
echo "Waiting 30s for instances to terminate..."
sleep 30

# 2. Delete instance templates (CRITICAL - was missing!)
echo "Deleting instance templates..."
gcloud compute instance-templates list --project=$PROJECT --format="value(name)" | grep $PATTERN | \
while read template; do
  echo "  Deleting template: $template"
  gcloud compute instance-templates delete $template --project=$PROJECT --quiet || true
done

# 3. Delete disks
echo "Deleting disks..."
gcloud compute disks list --project=$PROJECT --format="value(name,zone)" | grep $PATTERN | \
while read name zone; do
  echo "  Deleting disk: $name (zone: $zone)"
  gcloud compute disks delete $name --zone=$zone --project=$PROJECT --quiet || true
done

# 4. Delete addresses
echo "Deleting addresses..."
gcloud compute addresses list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read name region; do
  echo "  Deleting address: $name (region: $region)"
  gcloud compute addresses delete $name --region=$region --project=$PROJECT --quiet || true
done

# 5. Delete filestore
echo "Deleting filestore instances..."
gcloud filestore instances list --project=$PROJECT --format="value(name,location)" | grep $PATTERN | \
while read name location; do
  echo "  Deleting filestore: $name (location: $location)"
  gcloud filestore instances delete $name --location=$location --project=$PROJECT --quiet || true
done

# 6. Delete buckets (be careful - this deletes all data!)
echo "Deleting GCS buckets..."
gsutil ls -p $PROJECT | grep $PATTERN | while read bucket; do
  echo "  Deleting bucket: $bucket"
  gsutil -m rm -r $bucket || true
done

# 7. Delete routers
echo "Deleting routers..."
gcloud compute routers list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read name region; do
  echo "  Deleting router: $name (region: $region)"
  gcloud compute routers delete $name --region=$region --project=$PROJECT --quiet || true
done

# 8. Delete firewall rules
echo "Deleting firewall rules..."
gcloud compute firewall-rules list --project=$PROJECT --format="value(name)" | grep $PATTERN | \
while read rule; do
  echo "  Deleting firewall rule: $rule"
  gcloud compute firewall-rules delete $rule --project=$PROJECT --quiet || true
done

# 9. Delete subnets
echo "Deleting subnets..."
gcloud compute networks subnets list --project=$PROJECT --format="value(name,region)" | grep $PATTERN | \
while read subnet region; do
  echo "  Deleting subnet: $subnet (region: $region)"
  gcloud compute networks subnets delete $subnet --region=$region --project=$PROJECT --quiet || true
done

# 10. Delete networks
echo "Deleting networks..."
gcloud compute networks list --project=$PROJECT --format="value(name)" | grep $PATTERN | \
while read network; do
  echo "  Deleting network: $network"
  gcloud compute networks delete $network --project=$PROJECT --quiet || true
done

# 11. Delete resource policies (placement groups)
echo "Deleting resource policies..."
gcloud compute resource-policies list --project=$PROJECT --format="value(name,region)" 2>/dev/null | grep $PATTERN | \
while read name region; do
  echo "  Deleting resource policy: $name (region: $region)"
  gcloud compute resource-policies delete $name --region=$region --project=$PROJECT --quiet || true
done

echo ""
echo "=== Cleanup complete! ==="
echo ""
echo "Verifying cleanup..."
echo "Remaining instances:"
gcloud compute instances list --project=$PROJECT | grep $PATTERN || echo "  None"
echo "Remaining templates:"
gcloud compute instance-templates list --project=$PROJECT | grep $PATTERN || echo "  None"
echo "Remaining networks:"
gcloud compute networks list --project=$PROJECT | grep $PATTERN || echo "  None"
echo ""
echo "✅ Ready for fresh deployment!"
