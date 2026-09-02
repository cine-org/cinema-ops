# Init Instance

> Local WSL — prepare the instance to act as a remote staging node.

## 1. SSH server

Enable SSH so the WSL instance can be accessed remotely over the Tailscale network.

### Mirror

#### 1. Enable Mirrored Networking

Allow WSL to share the host's network interfaces.

**Windows:**

```text
C:\Users\<user>\.wslconfig
```

```ini
[wsl2]
networkingMode=mirrored
```

Restart WSL:

```powershell
wsl --shutdown
```

Check:

```bash
ip addr
hostname -I
```

#### 2. Enable systemd

Enable `systemd` so services such as SSH can be managed with `systemctl`.

**Ubuntu (WSL):**

```bash
sudo nano /etc/wsl.conf
```

```ini
[boot]
systemd=true
```

Restart WSL:

```powershell
wsl --shutdown
```

Check:

```bash
ps -p 1 -o comm= # systemd
```

### Install SSH Server

Install and start the OpenSSH server:

```bash
sudo apt install -y openssh-server
```

Enable:

```bash
sudo systemctl enable --now ssh
```

Check status:

```bash
sudo systemctl status ssh
```

## 2. Install Tailscale

Connect the WSL instance to the private Tailscale network so it can be accessed without exposing SSH to the public Internet.

Install:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Connect:

```bash
sudo tailscale up
```

Get IP:

```bash
tailscale ip
```

SSH:

```bash
ssh <user>@<tailscale-ip>
```
