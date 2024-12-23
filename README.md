# Gitea Docker Image for Raspberry Pi armv6 (Rpi 1 model b)

This repository is based on [Docker rpi Gitea](https://github.com/strobh/docker-rpi-gitea) and the official repository of [Gitea](https://github.com/go-gitea/gitea)
Contains the docker image to run Gitea in your rpi 1
By default uses the Gitea version 1.22.6 and alpine:3.20

## Build image

```
docker build -t rpi-gitea .
```

## Run image

Use docker-engine

```
docker run -it -p 2200:22 -p 3000:3000 -v ~/gitea:/data rpi-gitea
```

Or use docker-compose

```
version: "3"
services:
  web:
    image: ghcr.io/cumal/rpi-gitea:arm
    restart: always
    volumes:
      - ./teampass-html:/data
    ports:
      - 2200:22
      - 3000:3000
```
