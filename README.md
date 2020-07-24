# Ankhmorpork management and deployment system

## Installation

### Step-by-step instructions

1. Flash SD card with ubuntu 20.04 arm64
2. Configure ssh key-based login (first password is `raspberry`)
```bash
ssh-copy-id pi@<ip_of_host>
```
3. Install dependencies
```bash
apt install -y git python3-jmespath python3-pip
pip3 install ansible>=2.9.7
```
4. Clone this repository
```bash
git clone https://github.com/thaum-xyz/ankhmorpork.git config
```
5. Go into `ansible/` subdirectory in repository directory
6. Run `ansible-playbook 00_site.yml`

