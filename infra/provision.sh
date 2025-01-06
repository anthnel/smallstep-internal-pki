incus launch images:ubuntu/noble/cloud ca-server --profile default --profile cloud-init-profile
incus launch images:ubuntu/noble/cloud reverse-proxy --profile default --profile cloud-init-profile
incus launch images:ubuntu/noble/cloud client --profile default --profile cloud-init-profile
