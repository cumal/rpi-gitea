# Build stage
FROM docker.io/library/golang:1.23-alpine3.21 AS build-env

ARG GITEA_VERSION=1.22.6
ARG REPO_URL=https://github.com/go-gitea/gitea.git

# Build deps
RUN apk --no-cache add \
    build-base \
    git \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/*

# Setup repo
WORKDIR ${GOPATH}/src/code.gitea.io/gitea

# Checkout version if set
RUN git clone --depth 1 --branch v${GITEA_VERSION} ${REPO_URL} .

# Begin env-to-ini build
RUN go build -v contrib/environment-to-ini/environment-to-ini.go

# Set permissions
RUN chmod 755 /go/src/code.gitea.io/gitea/environment-to-ini
RUN chmod 644 /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete

FROM alpine:3.20

ARG BUILD_VERSION=1.22.6
ARG REPO_URL=https://github.com/go-gitea/gitea.git

# Ports that are listened on in the container
# Can be matched to other ports on the host via `docker run`
EXPOSE 22 3000

# Directory in the container that is mounted from the host
VOLUME /data

# Checks whether gitea is listening on port 3000
# Enables docker to automatically restart container if it is not healthy
HEALTHCHECK --interval=1m --timeout=10s \
    CMD nc -z localhost 3000 || exit 1

# Default environment variables for gitea
ENV USER=git
ENV GITEA_CUSTOM=/data/git

# Create gitea group and user
# UID and GID in container must match those of user on host (usually pi: 1000)
RUN addgroup \
        -S \
        -g 1000 \
        git \
    && adduser \
        -S -D -H \
        -u 1000 \
        -h /data/git \
        -G git \
        -s /bin/bash \
        -g "" \
        git \
    && echo "git:$(dd if=/dev/urandom bs=24 count=1 status=none | base64)" | chpasswd

# Install build dependencies (will be deleted from the image after the build)
RUN apk --no-cache --virtual .build-deps add \
    rsync

# Install dependencies
RUN apk --no-cache add \
    bash \
    ca-certificates \
    curl \
    gettext \
    git \
    linux-pam \
    openssh \
    s6 \
    sqlite \
    su-exec \
    gnupg \
    tzdata

# Pull docker files (sparse checkout: https://stackoverflow.com/a/13738951),
# merge them into /etc and /usr/bin/ with `rsync` and delete repository again
RUN mkdir /gitea-docker \
    && cd /gitea-docker \
    && git clone --depth 1 --branch v${BUILD_VERSION} ${REPO_URL} . \
    && rsync -av /gitea-docker/docker/root/ / \
    && rm -rf /gitea-docker

# Edit /etc/templates/sshd_config
# Remove `ssh-rsa` algorithm from option `CASignatureAlgorithms`
# This algorithm was removed in OpenSSH 8.2
RUN sed '/^CASignatureAlgorithms/s/,ssh-rsa//' /etc/templates/sshd_config > /etc/templates/sshd_config.tmp && mv /etc/templates/sshd_config.tmp /etc/templates/sshd_config

# Get gitea and verify signature
RUN mkdir -p /app/gitea \
    && gpg --keyserver keys.openpgp.org --recv 7C9E68152594688862D62AF62D9AE806EC1592E2 \
    && curl -sLo /app/gitea/gitea https://github.com/go-gitea/gitea/releases/download/v${BUILD_VERSION}/gitea-${BUILD_VERSION}-linux-arm-6 \
    && curl -sLo /app/gitea/gitea.asc https://github.com/go-gitea/gitea/releases/download/v${BUILD_VERSION}/gitea-${BUILD_VERSION}-linux-arm-6.asc \
    && gpg --verify /app/gitea/gitea.asc /app/gitea/gitea \
    && chmod 0755 /app/gitea/gitea \
    && ln -fns /app/gitea/gitea /usr/local/bin/gitea \
    && rm -rf /root/.gnupg

# Delete build dependencies
RUN apk del .build-deps

# Entrypoint
ENTRYPOINT ["/usr/bin/entrypoint"]
CMD ["/bin/s6-svscan", "/etc/s6"]

COPY --from=build-env /go/src/code.gitea.io/gitea/environment-to-ini /usr/local/bin/environment-to-ini
COPY --from=build-env /go/src/code.gitea.io/gitea/contrib/autocompletion/bash_autocomplete /etc/profile.d/gitea_bash_autocomplete.sh
