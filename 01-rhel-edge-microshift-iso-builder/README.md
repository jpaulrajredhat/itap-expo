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

25. To set static IP after OS is installed, use following commands.

```shell
nmcli conn show
```

```shell
nmcli conn mod <con-name> ipv4.method manual ipv4.add (static-IPaddress)/24 ipv4.dns 8.8.8.8,(additional-dns-if-required) ipv4.gateway (gateway-address)
```


<!-- oc kustomize ./kepler-manifests | grep "image:" | grep -oE '[^ ]+$' | while read line; do echo -e "[[containers]]\nsource = \"${line}\"\n"; done >>kepler-manifest.toml -->

<!-- 
!!!!!!! Tested installing packages in local !!!!!!!

sudo dnf install microshift* -y
Updating Subscription Management repositories.
Last metadata expiration check: 18:48:16 ago on Monday 30 September 2024 12:28:12 PM.
Dependencies resolved.
================================================================================
 Package                  Arch   Version
                                     Repository                            Size
================================================================================
Installing:
 microshift               x86_64 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     52 M
 microshift-greenboot     noarch 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     20 k
 microshift-multus        x86_64 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     22 k
 microshift-multus-release-info
                          noarch 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     14 k
 microshift-networking    x86_64 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     20 k
 microshift-olm           x86_64 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     68 k
 microshift-olm-release-info
                          noarch 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     14 k
 microshift-release-info  noarch 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     17 k
 microshift-selinux       noarch 4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     25 k
Installing dependencies:
 NetworkManager-ovs       x86_64 1:1.46.0-19.el9_4
                                     rhel-9-for-x86_64-appstream-rpms      64 k
 conntrack-tools          x86_64 1.4.7-2.el9
                                     rhel-9-for-x86_64-appstream-rpms     239 k
 cri-o                    x86_64 1.29.8-4.rhaos4.16.git7c340a9.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     18 M
 cri-tools                x86_64 1.29.0-4.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms    9.5 M
 greenboot                x86_64 0.15.6-1.el9_4
                                     rhel-9-for-x86_64-appstream-rpms      43 k
 libnetfilter_cthelper    x86_64 1.0.0-22.el9
                                     rhel-9-for-x86_64-appstream-rpms      26 k
 libnetfilter_cttimeout   x86_64 1.0.0-19.el9
                                     rhel-9-for-x86_64-appstream-rpms      25 k
 libnetfilter_queue       x86_64 1.0.5-1.el9
                                     rhel-9-for-x86_64-appstream-rpms      31 k
 openshift-clients        x86_64 4.16.0-202409032335.p0.gc44c839.assembly.stream.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms     52 M
 openvswitch-selinux-extra-policy
                          noarch 1.0-36.el9fdp
                                     fast-datapath-for-rhel-9-x86_64-rpms  11 k
 openvswitch3.3           x86_64 3.3.0-40.el9fdp
                                     fast-datapath-for-rhel-9-x86_64-rpms 6.8 M
 runc                     x86_64 4:1.1.14-1.rhaos4.16.el9
                                     rhocp-4.16-for-rhel-9-x86_64-rpms    3.1 M

Transaction Summary
================================================================================
Install  21 Packages

Total download size: 142 M
Installed size: 514 M
Downloading Packages:
(1/21): libnetfilter_cthelper-1.0.0-22.el9.x86_  40 kB/s |  26 kB     00:00    
(2/21): openvswitch-selinux-extra-policy-1.0-36  17 kB/s |  11 kB     00:00    
(3/21): libnetfilter_cttimeout-1.0.0-19.el9.x86  69 kB/s |  25 kB     00:00    
(4/21): libnetfilter_queue-1.0.5-1.el9.x86_64.r  70 kB/s |  31 kB     00:00    
(5/21): conntrack-tools-1.4.7-2.el9.x86_64.rpm  470 kB/s | 239 kB     00:00    
(6/21): NetworkManager-ovs-1.46.0-19.el9_4.x86_ 144 kB/s |  64 kB     00:00    
(7/21): greenboot-0.15.6-1.el9_4.x86_64.rpm     123 kB/s |  43 kB     00:00    
(8/21): cri-tools-1.29.0-4.el9.x86_64.rpm       2.8 MB/s | 9.5 MB     00:03    
(9/21): cri-o-1.29.8-4.rhaos4.16.git7c340a9.el9.x86_64.rpm                                                               2.0 MB/s |  18 MB     00:09    
(10/21): openvswitch3.3-3.3.0-40.el9fdp.x86_64.rpm                                                                       390 kB/s | 6.8 MB     00:17    
(11/21): runc-1.1.14-1.rhaos4.16.el9.x86_64.rpm                                                                          668 kB/s | 3.1 MB     00:04    
(12/21): microshift-greenboot-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch.rpm                           7.3 kB/s |  20 kB     00:02    
(13/21): microshift-multus-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64.rpm                              7.5 kB/s |  22 kB     00:02    
(14/21): openshift-clients-4.16.0-202409032335.p0.gc44c839.assembly.stream.el9.x86_64.rpm                                2.1 MB/s |  52 MB     00:24    
(15/21): microshift-multus-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch.rpm                 5.7 kB/s |  14 kB     00:02    
(16/21): microshift-olm-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64.rpm                                 172 kB/s |  68 kB     00:00    
(17/21): microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64.rpm                          6.9 kB/s |  20 kB     00:02    
(18/21): microshift-olm-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch.rpm                    5.3 kB/s |  14 kB     00:02    
(19/21): microshift-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch.rpm                        6.4 kB/s |  17 kB     00:02    
(20/21): microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch.rpm                             9.5 kB/s |  25 kB     00:02    
(21/21): microshift-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64.rpm                                                                                  2.2 MB/s |  52 MB     00:23    
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Total                                                                                                                                                                 3.5 MB/s | 142 MB     00:41     
Running transaction check
Transaction check succeeded.
Running transaction test
Transaction test succeeded.
Running transaction
  Preparing        :                                                                                                                                                                             1/1 
  Installing       : microshift-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                       1/21 
  Installing       : runc-4:1.1.14-1.rhaos4.16.el9.x86_64                                                                                                                                       2/21 
  Installing       : cri-o-1.29.8-4.rhaos4.16.git7c340a9.el9.x86_64                                                                                                                             3/21 
  Running scriptlet: cri-o-1.29.8-4.rhaos4.16.git7c340a9.el9.x86_64                                                                                                                             3/21 
Created symlink /etc/systemd/system/multi-user.target.wants/crio-subid.service → /usr/lib/systemd/system/crio-subid.service.
Created symlink /etc/systemd/system/crio.service.wants/crio-subid.service → /usr/lib/systemd/system/crio-subid.service.

  Installing       : openshift-clients-4.16.0-202409032335.p0.gc44c839.assembly.stream.el9.x86_64                                                                                               4/21 
  Installing       : cri-tools-1.29.0-4.el9.x86_64                                                                                                                                              5/21 
  Installing       : greenboot-0.15.6-1.el9_4.x86_64                                                                                                                                            6/21 
  Running scriptlet: greenboot-0.15.6-1.el9_4.x86_64                                                                                                                                            6/21 
Created symlink /etc/systemd/system/multi-user.target.wants/greenboot-healthcheck.service → /usr/lib/systemd/system/greenboot-healthcheck.service.
Created symlink /etc/systemd/system/boot-complete.target.requires/greenboot-healthcheck.service → /usr/lib/systemd/system/greenboot-healthcheck.service.
Created symlink /etc/systemd/system/multi-user.target.wants/greenboot-task-runner.service → /usr/lib/systemd/system/greenboot-task-runner.service.
Created symlink /etc/systemd/system/redboot.target.requires/redboot-task-runner.service → /usr/lib/systemd/system/redboot-task-runner.service.
Created symlink /etc/systemd/system/multi-user.target.wants/greenboot-status.service → /usr/lib/systemd/system/greenboot-status.service.
Created symlink /etc/systemd/system/ostree-finalize-staged.service.requires/greenboot-grub2-set-counter.service → /usr/lib/systemd/system/greenboot-grub2-set-counter.service.
Created symlink /etc/systemd/system/multi-user.target.wants/greenboot-grub2-set-success.service → /usr/lib/systemd/system/greenboot-grub2-set-success.service.
Created symlink /etc/systemd/system/greenboot-healthcheck.service.requires/greenboot-rpm-ostree-grub2-check-fallback.service → /usr/lib/systemd/system/greenboot-rpm-ostree-grub2-check-fallback.service.
Created symlink /etc/systemd/system/redboot.target.wants/redboot-auto-reboot.service → /usr/lib/systemd/system/redboot-auto-reboot.service.

  Installing       : NetworkManager-ovs-1:1.46.0-19.el9_4.x86_64                                                                                                                                7/21 
  Installing       : libnetfilter_queue-1.0.5-1.el9.x86_64                                                                                                                                      8/21 
  Installing       : libnetfilter_cttimeout-1.0.0-19.el9.x86_64                                                                                                                                 9/21 
  Installing       : libnetfilter_cthelper-1.0.0-22.el9.x86_64                                                                                                                                 10/21 
  Installing       : conntrack-tools-1.4.7-2.el9.x86_64                                                                                                                                        11/21 
  Running scriptlet: conntrack-tools-1.4.7-2.el9.x86_64                                                                                                                                        11/21 
  Running scriptlet: openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                                                                                                     12/21 
  Installing       : openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                                                                                                     12/21 
  Running scriptlet: openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                                                                                                     12/21 
  Running scriptlet: openvswitch3.3-3.3.0-40.el9fdp.x86_64                                                                                                                                     13/21 
  Installing       : openvswitch3.3-3.3.0-40.el9fdp.x86_64                                                                                                                                     13/21 
  Running scriptlet: openvswitch3.3-3.3.0-40.el9fdp.x86_64                                                                                                                                     13/21 
  Installing       : microshift-greenboot-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                         14/21 
  Running scriptlet: microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                           15/21 
  Installing       : microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                           15/21 
  Running scriptlet: microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                           15/21 
  Installing       : microshift-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                                   16/21 
  Running scriptlet: microshift-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                                   16/21 
  Running scriptlet: microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                        17/21 
  Installing       : microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                        17/21 
  Running scriptlet: microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                        17/21 
Warning: The unit file, source configuration file or drop-ins of NetworkManager.service changed on disk. Run 'systemctl daemon-reload' to reload units.

  Installing       : microshift-multus-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                            18/21 
  Running scriptlet: microshift-multus-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                            18/21 
  Installing       : microshift-olm-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                               19/21 
  Installing       : microshift-multus-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                               20/21 
  Installing       : microshift-olm-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                  21/21 
  Running scriptlet: openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                                                                                                     21/21 
  Running scriptlet: microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                           21/21 
  Running scriptlet: microshift-olm-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                  21/21 
  Verifying        : openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                                                                                                      1/21 
  Verifying        : openvswitch3.3-3.3.0-40.el9fdp.x86_64                                                                                                                                      2/21 
  Verifying        : libnetfilter_cthelper-1.0.0-22.el9.x86_64                                                                                                                                  3/21 
  Verifying        : libnetfilter_cttimeout-1.0.0-19.el9.x86_64                                                                                                                                 4/21 
  Verifying        : libnetfilter_queue-1.0.5-1.el9.x86_64                                                                                                                                      5/21 
  Verifying        : conntrack-tools-1.4.7-2.el9.x86_64                                                                                                                                         6/21 
  Verifying        : NetworkManager-ovs-1:1.46.0-19.el9_4.x86_64                                                                                                                                7/21 
  Verifying        : greenboot-0.15.6-1.el9_4.x86_64                                                                                                                                            8/21 
  Verifying        : cri-tools-1.29.0-4.el9.x86_64                                                                                                                                              9/21 
  Verifying        : openshift-clients-4.16.0-202409032335.p0.gc44c839.assembly.stream.el9.x86_64                                                                                              10/21 
  Verifying        : cri-o-1.29.8-4.rhaos4.16.git7c340a9.el9.x86_64                                                                                                                            11/21 
  Verifying        : runc-4:1.1.14-1.rhaos4.16.el9.x86_64                                                                                                                                      12/21 
  Verifying        : microshift-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                                   13/21 
  Verifying        : microshift-greenboot-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                         14/21 
  Verifying        : microshift-multus-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                            15/21 
  Verifying        : microshift-multus-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                               16/21 
  Verifying        : microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                        17/21 
  Verifying        : microshift-olm-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                                                                                               18/21 
  Verifying        : microshift-olm-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                  19/21 
  Verifying        : microshift-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                      20/21 
  Verifying        : microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                                                                                           21/21 
Installed products updated.

Installed:
  NetworkManager-ovs-1:1.46.0-19.el9_4.x86_64                                                     conntrack-tools-1.4.7-2.el9.x86_64                                                                
  cri-o-1.29.8-4.rhaos4.16.git7c340a9.el9.x86_64                                                  cri-tools-1.29.0-4.el9.x86_64                                                                     
  greenboot-0.15.6-1.el9_4.x86_64                                                                 libnetfilter_cthelper-1.0.0-22.el9.x86_64                                                         
  libnetfilter_cttimeout-1.0.0-19.el9.x86_64                                                      libnetfilter_queue-1.0.5-1.el9.x86_64                                                             
  microshift-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                         microshift-greenboot-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                 
  microshift-multus-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                  microshift-multus-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch       
  microshift-networking-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64              microshift-olm-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.x86_64                       
  microshift-olm-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch        microshift-release-info-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch              
  microshift-selinux-4.16.14-202409191303.p0.ga21ff6e.assembly.4.16.14.el9.noarch                 openshift-clients-4.16.0-202409032335.p0.gc44c839.assembly.stream.el9.x86_64                      
  openvswitch-selinux-extra-policy-1.0-36.el9fdp.noarch                                           openvswitch3.3-3.3.0-40.el9fdp.x86_64                                                             
  runc-4:1.1.14-1.rhaos4.16.el9.x86_64                                                           

Complete! -->

<!-- 

Default config yaml for microshift after install

sudo microshift show-config
apiServer:
  advertiseAddress: 10.44.0.0
  subjectAltNames:
  - rhel9-rpi5-1.systems
debugging:
  logLevel: Normal
dns:
  baseDomain: example.com
etcd:
  memoryLimitMB: 0
manifests:
  kustomizePaths:
  - /usr/lib/microshift/manifests
  - /usr/lib/microshift/manifests.d/*
  - /etc/microshift/manifests
  - /etc/microshift/manifests.d/*
network:
  clusterNetwork:
  - 10.42.0.0/16
  serviceNetwork:
  - 10.43.0.0/16
  serviceNodePortRange: 30000-32767
node:
  hostnameOverride: rhel9-rpi5-1.systems
  nodeIP: 192.168.31.215 -->