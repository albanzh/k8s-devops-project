# Fill in your real values here.
# This file is gitignored.

subscription_id   = "90910ed1-4494-4f29-90e1-a275ea91ac64"
letsencrypt_email = "alban.zheku@gmail.com"
username          = "azureuser"

# Allow SSH + K8s API from your public IP range(s).
# Get yours: curl -s ifconfig.me
# Then run:  whois <ip> | grep -iE "route:|inetnum:"
admin_source_cidr = ["0.0.0.0/0"]
