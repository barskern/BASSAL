# Barskern's Automatic Setup Scripts for ArchLinux

![](https://img.shields.io/badge/status-under--development-orange.svg?style=flat-square)

_This repo is inspired by Luke Smith's [LARBS](https://github.com/LukeSmithxyz/LARBS/)_

These scripts are my personal scripts for setting up a base system using ArchLinux and i3.

## Using the scripts

Using git:

```shell
git clone https://github.com/barskern/BASSAL.git; cd BASSAL; sudo ./dist/bassal_main.sh
```

Without git:

```shell
curl -O https://raw.githubusercontent.com/barskern/BASSAL/master/dist/bassal_main.sh; sudo ./bassal_main.sh
```

## Full setup

Included in this repository is also a script to run a full install from a LiveUSB running ArchLinux. This will **partition** a disk and setup the environment automatically. This is primarily included for my own purposes of quickly installing my preferences on blank computer. Hence use with **care**!

```shell
git clone https://github.com/barskern/BASSAL.git; cd BASSAL; sudo ./dist/bassal_live.sh
```

Without git:

```shell
curl -O https://raw.githubusercontent.com/barskern/BASSAL/master/dist/bassal_live.sh; sudo ./bassal_live.sh
```
