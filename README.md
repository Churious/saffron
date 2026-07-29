# saffron
Saffron is a spice derived from the flower of Crocus sativus, commonly known as the "saffron crocus". 

## Install

### Chocolatey
Powershell
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

### Terraform
[Chocolatey](https://github.com/Churious/saffron/blob/main/README.md#chocolatey)
```powershell
choco install terraform -y
```

### Git
[Chocolatey](https://github.com/Churious/saffron/blob/main/README.md#chocolatey)
```powershell
choco install git.install -y
```

### VSCode
[Chocolatey](https://github.com/Churious/saffron/blob/main/README.md#chocolatey)
```powershell
choco install vscode -y
```
### 

## Scripts

### Bastion (EC2/Cloudshell)
Helm, kubectl, eksctl install
```bash
curl -fsSL https://raw.githubusercontent.com/Churious/saffron/refs/heads/main/bastion.sh | bash
```
