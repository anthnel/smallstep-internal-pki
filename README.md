# smallstep-internal-pki

Création d'une PKI privée en utilisant Ansible et [Smallstep](https://smallstep.com/docs/).

L'infrastructure pour tester les playbooks Ansible est gérées au moyen de [Incus](https://linuxcontainers.org/incus/).

## Prérequis 

* WSL2 avec Ubuntu 24
* [Installation de Incus](https://linuxcontainers.org/incus/docs/main/tutorial/first_steps/)
* Installation de Ansible
* Installation des roles et collections utilisées (`ansible-galaxy install -r requirements.yml`)

## Préparation pour les conteneurs systèmes

Ansible utilise une connexion SSH pour l'exécution des playbooks. Par facilité, un profil Incus a été créé pour automatiser les étapes préalables nécessaires à l'exécution des playbooks.

```sh
$ incus profile show cloud-init-profile
config:
  cloud-init.user-data: |
    #cloud-config
    users:
    - name: ansible
      groups: sudo
      shell: /bin/bash
      ssh_authorized_keys:
        - ssh-ed25519 ...
      sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    package_upgrade: true
    packages:
      - openssh-server
    runcmd:
      - [touch, /tmp/cloud-init-complete]
description: ""
devices: {}
name: cloud-init-profile
```

Le profil contient une configuration cloud-init pour : 

* installer une clé publique pour permettre la connexion SSH dans le conteneur
* installer le package openssh-server
* créer l'utilisateur ansible et lui permettre d'exécuter des commandes root sans mot de passe

Les images Incus doivent être des images compatibles cloud-init pour bénéficier de ce profil.

L'instanciation d'un conteneur système est réalisée de cette manière :

```sh
$ incus launch images:ubuntu/noble/cloud ca-server --profile default --profile cloud-init-profile
```

Ensuite il est possible de directement se connecter en SSH :

```sh
$ ssh ansible@ca-server
ansible@ca-server:~$ sudo -s
root@ca-server:/home/ansible#
```

## Création des conteneurs systèmes

```sh
infra$ ./provision.sh
Launching ca-server
Launching reverse-proxy
Launching client
$ incus list
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
|     NAME      |  STATE  |         IPV4         |                     IPV6                      |   TYPE    | SNAPSHOTS |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
| ca-server     | RUNNING | 10.215.55.127 (eth0) | fd42:312e:496f:6ce7:216:3eff:fefb:fdf7 (eth0) | CONTAINER | 0         |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
| client        | RUNNING | 10.215.55.27 (eth0)  | fd42:312e:496f:6ce7:216:3eff:feb8:8a7e (eth0) | CONTAINER | 0         |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
| reverse-proxy | RUNNING | 10.215.55.202 (eth0) | fd42:312e:496f:6ce7:216:3eff:fef6:797c (eth0) | CONTAINER | 0         |
+---------------+---------+----------------------+-----------------------------------------------+-----------+-----------+
```

## Création de la PKI privée

Exécution du playbook `ca-server.yaml` :

```sh
$ ./ca-server.yaml
...
PLAY RECAP 
ca-server                  : ok=38   changed=14   unreachable=0    failed=0    skipped=22   rescued=0    ignored=0 
```

Vérification de l'installation :

```sh
$ incus shell ca-server
root@ca-server:~# step-cli ca health --ca-url https://ca-server --root /etc/step-ca/certs/root_ca.crt
ok
```

Récupération de l'empreinte du serveur :

```sh
root@ca-server:~#step-cli certificate fingerprint /etc/step-ca/certs/root_ca.crtn
798307f3b0afa2fec639a5ef3b5037f029d8ce64a6c2168f3f605966354e6cd5 
```
Cette empreinte est nécessaire pour configurer la communication entre les clients et le serveur.

## Création d'un reverse proxy nginx avec gestion TLS

Exécution du playbook `reverse-proxy.yaml` :

```sh
$ ./reverse-proxy.yaml
...
PLAY RECAP 
reverse-proxy              : ok=42   changed=3    unreachable=0    failed=0    skipped=36   rescued=0    ignored=0   
```

Le playbook exécute ces actions :

* Installation de NGINX
* Installation des packages `certbot` et `python3-certbot-nginx`
    * permettent d'automatiser la génération des certificats TLS
* Configuration de la communication de ce serveur avec le serveur CA
* Installation de la configuration simple HTTP de nginx
* Génération des certificats et de la configuration HTTPS avec certbot
* Ajout de l'hôte incus dans le /etc/hosts local (Ubuntu 24 sous WSL2)

Le reverse proxy est accessible en https, voici un test depuis l'hôte Ubuntu 24 sous WSL2 :

```sh
$ curl https://reverse-proxy/index.html
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.

# comme le root CA n'est pas installé sur l'hôte Ubuntu 24 il faut ignorer la vérification du certificat
$ curl -k https://reverse-proxy/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Nginx installed by Ansible!</h1>
<p>If you see this page, Ansible successfully installed nginx.</p>

<p>Running on reverse-proxy</p>

<p><em>Thank you for using nginx.</em></p>
</body>
```

Effectuons un test sous un client dont le root CA est bien présent.

## Création d'un serveur de test pour interroger le reverse-proxy

Exécution du playbook `client.yaml` 

```sh
$ ./client.yaml
...
PLAY RECAP 
client                     : ok=17   changed=0    unreachable=0    failed=0    skipped=10   rescued=0    ignored=0 
```

Test d'appel du reverse proxy :

```sh
# connexion dans le conteneur système client
$ incus shell client
root@client:~# curl https://reverse-proxy/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Nginx installed by Ansible!</h1>
<p>If you see this page, Ansible successfully installed nginx.</p>

<p>Running on reverse-proxy</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
# la vérification TLS s'est correctement effectuée
```
