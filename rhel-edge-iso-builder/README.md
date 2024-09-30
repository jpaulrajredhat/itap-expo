

# Building Red Hat Device Edge with microshift ISO using composer-cli

Prerequistes ( Used for this demo ) 
- Red Hat enterprise linux 9 ( In bare metal or Virtual Machine )
- Red Hat subscription to enable rhocp and fast-datapath

**Note**: *If below commands doesnt work even for sudo user, try adding the user to weldr group*
```shell
sudo usermod -aG weldr <youruser>
```
*If still cant able to run even after adding the user to weldr group, then run the commands as ***root user***.*

1. Install necessary tools to build ISO file with composer-cli

```shell
sudo dnf install osbuild-composer composer-cli cockpit-composer bash-completion firewalld createrepo_c podman yum-utils -y
```

2. (Optional) - To build iso file from RHEL cockpit

```shell
sudo firewall-cmd --add-service=cockpit && firewall-cmd --add-service=cockpit --permanent
```
```shell
sudo systemctl enable cockpit.socket --now
```

3. Enable osbuilder composer service

```shell
sudo systemctl enable osbuild-composer.socket --now
```
```shell
source /etc/bash_completion.d/composer-cli
```

4. Enable rhocp and fast-datapath subscriptions

```shell
sudo subscription-manager repos --enable rhocp-4.16-for-rhel-9-$(uname -i)-rpms --enable fast-datapath-for-rhel-9-$(uname -i)-rpms
```

5. Create directory to store packages to be downloaded from rhocp and fast-datapath repositories

```shell
sudo mkdir -p /var/repos/microshift-local
```

6. Using reposync download all the packages from rhocp and fast-datapath repository

```shell
sudo reposync --arch=$(uname -i) --arch=noarch --gpgcheck \
    --download-path /var/repos/microshift-local \
    --repo=rhocp-4.16-for-rhel-9-$(uname -i)-rpms \
    --repo=fast-datapath-for-rhel-9-$(uname -i)-rpms
```

7. Remove any duplicate packages from the rhocp and fast-datapath repos downloaded in /var/repos/microshift-local

```shell
find /var/repos/microshift-local -name "*.rpm" | awk -F'/' '{print $NF}' | sort | uniq -d | while read pkg; do find /var/repos/microshift-local -name "$pkg" | tail -n +2 | xargs rm -f; done
```

8. Using createrepo tool build custom repository with rhocp and fast-datapath repository packages

```shell
sudo createrepo /var/repos/microshift-local/
```

9. Create a toml file to create a blueprint for the custom repository  
( Refer [microshift-local-repo.toml](./microshift-local-repo.toml) )

```shell
sudo tee /var/repos/microshift-local/microshift-local-repo.toml > /dev/null <<EOF
id = "microshift-local"
name = "MicroShift local repo"
type = "yum-baseurl"
url = "file:////var/repos/microshift-local/"
check_gpg = false
check_ssl = false
system = false
EOF
```

10. Using composer-cli tool add the blueprint file 

```shell
sudo composer-cli sources add /var/repos/microshift-local/microshift-local-repo.toml
```
11. To verify packages added in microshift-local
```shell
sudo composer-cli sources info microshift-local
```

<!-- # PASSWORD="admin123"
# python3 -c 'import crypt, os; pw = os.getenv("PASSWORD"); print(crypt.crypt(pw))' -->

12. Create another toml file with all necessary packages and other customizations to be included in iso file, here microshift is included. This creates a ostree blueprint.   
(Refer [RHDE-microshift-ostree](./rhde-microshift-ostree.toml))

```shell
cat << EOF > rhde-microshift-ostree.toml
name = "rhde-microshift-ostree"
description = "RHDE Microshift Image"
version = "1.0.0"
modules = []
groups = []
distro=""

[[packages]]
name = "microshift"
version = "*"

[[packages]]
name = "openshift-clients"
version = "*"

[[packages]]
name = "git"
version = "*"

[[packages]]
name = "iputils"
version = "*"

[[packages]]
name = "bind-utils"
version = "*"

[[packages]]
name = "net-tools"
version = "*"

[[packages]]
name = "iotop"
version = "*"

[[packages]]
name = "redhat-release"
version = "*"

[[packages]]
name = "microshift-networking"
version = "*"

[[packages]]
name = "microshift-release-info"
version = "*"

[[packages]]
name = "microshift-selinux"
version = "*"

[customizations]
hostname = "ztp-microshift"

[customizations.firewall]
ports = ["6443:tcp"]

[customizations.firewall.services]
enabled = ["http", "https", "ntp", "dhcp", "ssh"]
disabled = ["telnet"]
[customizations.services]
enabled = ["microshift"]

[[customizations.user]]
name = "<USERNAME>"
password = "<PASSWORD_HERE>"
key = "<SSH_PUBLIC_KEY>"
groups = ["wheel"]
shell = "/usr/bin/bash"
description = "microshift user"

EOF
```
**Note**: *To Generate password for password = "<PASSWORD_HERE>" use the below command. This will prompt to enter password and provides encrypted password as output*

```shell
python3 -c 'import crypt,getpass;pw=getpass.getpass();print(crypt.crypt(pw) if (pw==getpass.getpass("Confirm: ")) else exit())'
```

13. Push the rhde-microshift-ostree toml file with composer-cli to create blueprint

```shell
sudo composer-cli blueprints push rhde-microshift-ostree.toml
```

14. Start building edge-commit image with rhde-microshift-ostree blueprint

```shell
sudo composer-cli compose start rhde-microshift-ostree edge-commit
```

15. Check for image build state. Wait unit it FINISHED.

```shell
sudo watch composer-cli compose status
```

16. The above command ***"composer-cli compose status"*** provides the image ID, using the image ID compose the image, this will create a tar file.

```shell
sudo composer-cli compose image <OSTREE_IMAGE_ID>
```

17. Extract the contents of the tar file.

```shell
tar -xvf <OSTREE_IMAGE_ID>-commit.tar
```

18. Now, create an docker image and run the container that hosts the custom packages extracted from ***"<OSTREE_IMAGE_ID>-commit.tar"***

Refer [nginx-conf](./nginx-conf)
```shell
cat > nginx << EOF
events {

}

http {
    server{
        listen 8080;
        root /usr/share/nginx/html;
                }
         }

pid /run/nginx.pid;
daemon off;
EOF 
```

Refer []()
```shell
cat > nginx-dockerfile << EOF
FROM registry.access.redhat.com/ubi9/ubi
RUN yum -y install nginx && yum clean all
COPY repo /usr/share/nginx/html/
COPY nginx-conf /etc/nginx.conf
EXPOSE 8080
CMD ["/usr/sbin/nginx", "-c", "/etc/nginx.conf"]
ARG commit
ADD ${commit} /usr/share/nginx/html/
EOF
```

```shell
podman build -t microshift-image-1.0.0 --build-arg commit=<OSTREE_IMAGE_ID>-commit.tar -f nginx-dockerfile .
```

```shell
podman run --name rpm-ostree-repository --rm -d -p 8080:8080 localhost/microshift-image-1.0.0:latest
```

19. Create new toml file, build ISO. (Refer [RHDE-microshift-ostree-installer](./rhde-microshift-ostree.toml))

```shell
cat > microshift-rpmostree-installer.toml << EOF
name = "microshift-rpmostree-installer"
description = ""
version = "1.0.0"
modules = []
groups = []
EOF
```

20. Now push the toml file to create blueprint for microshift-rpmostree-installer

```shell
sudo composer-cli blueprints push microshift-rpmostree-installer.toml
```

21. Create local repository manager with the nginx container and the microshift-rpmostree-installer blueprint using ostree edge-installer composer-cli method.

```shell
composer-cli compose start-ostree --ref rhel/9/x86_64/edge --url http://127.0.0.1:8080/repo microshift-rpmostree-installer edge-installer
```

```shell
composer-cli compose status
```

22. Compose the image for microshift-rpmostree-installer. This 

```shell
composer-cli compose image <INSTALLER_IMAGE_ID>
```

23. Create a kickstart file to auto complete basic setup of OS.  
( Refer [kickstart.ks](./kickstart.ks) )

```shell
cat > kickstart.ks << EOF
lang en_IN
keyboard --xlayouts='us'
timezone Asia/Kolkata --utc
zerombr
clearpart --all --initlabel
part /boot/efi --fstype=efi --size=200
part /boot --fstype=xfs --asprimary --size=800
part pv.01 --grow
volgroup rhel pv.01
logvol / --vgname=rhel --fstype=xfs --size=10000 --name=root
reboot
text
network --bootproto=dhcp
ostreesetup --nogpg --url=http://192.168.1.202:8080/repo --osname=rhel --remote=edge --ref=rhel/8/x86_64/edge

%post 
# Add the pull secret to CRI-O and set root user-only read/write permissions
cat > /etc/crio/openshift-pull-secret << EOF
<ENTER PULL SECRET>
EOF
chmod 600 /etc/crio/openshift-pull-secret
%end
%post
# Configure the firewall with the mandatory rules for MicroShift
firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16
firewall-offline-cmd --zone=trusted --add-source=169.254.169.1
mkdir -p ~/.kube/
cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config
chmod go-r ~/.kube/config
%end
EOF
```

24. Create a iso file with mkksiso to add the kickstart.ks file to the installer iso

```shell
mkksiso kickstart.ks <INSTALLER_IMAGE_ID>-installer.iso microshift-rpmostree-installer.iso
```