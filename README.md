# Ankhmorpork management and deployment system

## Installation

### Step-by-step instructions

1. Flash SD card with latest raspbian buster and add empty `/boot/ssh` file
2. Configure ssh key-based login (first password is `raspberry`)
```bash
ssh-copy-id pi@<ip_of_host>
```
2. Upgrade system
```bash
apt update
apt -y upgrade
```
3. Install dependencies
```bash
apt install -y git python3-jmespath python3-pip
pip3 install ansible ara
```
4. Clone this repository via HTTPS (not SSH!)
```bash
git clone https://github.com/thaum-xyz/ankhmorpork.git config
```
5. Go into repository directory
6. Configure [git credentials store](https://git-scm.com/docs/git-credential-store)
```bash
git config credential.helper store
git pull
```
7. Set git user
```bash
git config user.email "example@example.org"
git config user.name "example"
```
8. Create `/var/log/deploy` directory and change ownership to current user
8. Run `deploy.sh` script
9. Check if browser is up and reboot server

### All-in-one
```bash
# Flash SD
ssh-copy-id pi@<ip_of_host>
# login to host
sudo apt update && sudo apt -y upgrade
sudo apt install -y git python3-jmespath python3-pip && sudo pip3 install ansible ara
git clone https://github.com/thaum-xyz/ankhmorpork.git config
cd config
git config credential.helper store && git pull
git config user.email "example@example.org"
git config user.name "example"
sudo mkdir /var/log/deploy && sudo chown $(id -u):$(id -g) /var/log/deploy
./deploy.sh
```
