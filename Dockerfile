# jemalloc Builder
FROM buildpack-deps:stretch-scm as jemalloc

RUN set -ex; \
  apt-get update; \
  apt-get -y install procps binutils bzip2 wget tar make gcc autoconf; \
  rm -rf /var/lib/apt/lists/*;

ENV JEMALLOC_VERSION=5.2.1

RUN set -ex; \
  wget -nv -O /tmp/jemalloc.tar.bz2 https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2; \
  tar -xvf /tmp/jemalloc.tar.bz2; \
  cd ./jemalloc-${JEMALLOC_VERSION} && ./autogen.sh && ./configure --enable-prof &&  make -j8 && make install; \
  rm -rf /tmp/jemalloc.tar.bz2 ./jemalloc-${JEMALLOC_VERSION}

FROM buildpack-deps:stretch-scm

RUN set -ex; \
  apt-get update; \
  apt-get -y install gpg openjdk-8-dbg procps binutils graphviz libsnappy1v5 gettext-base wget libc6 libgcc1 libstdc++6; \
  rm -rf /var/lib/apt/lists/*


# Grab gosu for easy step-down from root
ENV GOSU_VERSION 1.11
RUN set -ex; \
  wget -nv -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)"; \
  wget -nv -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc"; \
  export GNUPGHOME="$(mktemp -d)"; \
  for server in ha.pool.sks-keyservers.net $(shuf -e \
                          hkp://p80.pool.sks-keyservers.net:80 \
                          keyserver.ubuntu.com \
                          hkp://keyserver.ubuntu.com:80 \
                          pgp.mit.edu) ; do \
      gpg --batch --keyserver "$server" --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 && break || : ; \
  done && \
  gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
  chmod +x /usr/local/bin/gosu; \
  gosu nobody true

# Configure Flink version
ENV FLINK_VERSION=1.9.3 \
    SCALA_VERSION=2.12 \
    GPG_KEY=6B6291A8502BA8F0913AE04DDEB95B05BF075300

# Prepare environment
ENV FLINK_HOME=/opt/flink
ENV PATH=$FLINK_HOME/bin:$PATH
RUN groupadd --system --gid=9999 flink && \
    useradd --system --home-dir $FLINK_HOME --uid=9999 --gid=flink flink
WORKDIR $FLINK_HOME

ENV FLINK_URL_FILE_PATH=flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_${SCALA_VERSION}.tgz
# Not all mirrors have the .asc files
ENV FLINK_TGZ_URL=https://archive.apache.org/dist/${FLINK_URL_FILE_PATH} \
    FLINK_ASC_URL=https://archive.apache.org/dist/${FLINK_URL_FILE_PATH}.asc

# Install Flink
RUN set -ex; \
  wget -nv -O flink.tgz "$FLINK_TGZ_URL"; \
  wget -nv -O flink.tgz.asc "$FLINK_ASC_URL"; \
  \
  export GNUPGHOME="$(mktemp -d)"; \
  for server in ha.pool.sks-keyservers.net $(shuf -e \
                          hkp://p80.pool.sks-keyservers.net:80 \
                          keyserver.ubuntu.com \
                          hkp://keyserver.ubuntu.com:80 \
                          pgp.mit.edu) ; do \
      gpg --batch --keyserver "$server" --recv-keys "$GPG_KEY" && break || : ; \
  done && \
  gpg --batch --verify flink.tgz.asc flink.tgz; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME" flink.tgz.asc; \
  \
  tar -xf flink.tgz --strip-components=1; \
  rm flink.tgz; \
  \
  chown -R flink:flink .;

# Install jemalloc
COPY --from=jemalloc /usr/local/bin/jeprof /usr/local/bin/jeprof
COPY --from=jemalloc /usr/local/lib/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

# Configure container
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 6123 8081
CMD ["help"]
