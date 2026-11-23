# GreenReso – Maquette

## Prérequis

- VMware Workstation
- ISO : `ubuntu.iso`, `win10.iso`, `winsrv.iso`

## Installation

### 1. Préparer les ISO

Créer le dossier `maquette/iso` et y placer les trois ISO :

```
maquette/iso
├── ubuntu.iso
├── win10.iso
└── winsrv.iso
```

### 2. Lancer l'installation

```sh
./maquette/install.sh
```

- **Windows 10 et Windows Server** : installation automatique.
- **Ubuntu** : installation manuelle.
  - Clavier en français.
  - « Next » partout.
  - Nom de machine, utilisateur et mot de passe : `ubuntu`.
  - Éteindre la VM une fois l'installation terminée.

### 3. Créer les machines

```sh
./maquette/creer.sh
```

Crée toutes les VM de GreenReso.

### 4. Importer dans Workstation

*File → Scan for Virtual Machines → Next → Keep the hierarchy of folders in library → Finish*

## Déployer une configuration

```sh
./maquette/deploy.sh <nom_de_la_vm> <chemin_du_script>
```

Exemple :

```sh
./maquette/deploy.sh SRV-AD01 ps/SRV-AD01.ps1
```