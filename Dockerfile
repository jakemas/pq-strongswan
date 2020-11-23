FROM ubuntu:20.04
MAINTAINER Jake Massimo <jakemas@amazon.com>
ENV VERSION="6.0dr3"

RUN \
  # install packages
  DEV_PACKAGES="wget unzip make gcc libssl-dev cmake ninja-build libgmp3-dev" && \
  apt-get -y update && \
  apt-get -y install iproute2 iputils-ping nano $DEV_PACKAGES && \
  \
  # download and build liboqs
  mkdir /liboqs && \
  cd /liboqs && \
  wget https://github.com/open-quantum-safe/liboqs/archive/master.zip && \
  unzip master.zip && \
  cd liboqs-master && \
  mkdir build && cd build && \
  cmake -GNinja -DOQS_USE_OPENSSL=ON -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=/usr .. && \
  ninja && ninja install && \
  cd / && rm -R /liboqs && \
  # download and build strongSwan IKEv2 daemon
  mkdir /strongswan-build && \
  cd /strongswan-build && \
  wget https://download.strongswan.org/strongswan-$VERSION.tar.bz2 && \
  tar xfj strongswan-$VERSION.tar.bz2 && \
  cd strongswan-$VERSION && \
  ./configure --prefix=/usr --sysconfdir=/etc      \
    --enable-oqs --enable-gcm --enable-ntru --enable-frodo && \
   make all && make install && \
   cd / && rm -R strongswan-build && \
   ln -s /usr/libexec/ipsec/charon charon && \
   \
   # clean up
   apt-get -y remove $DEV_PACKAGES && \
   apt-get -y autoremove && \
   apt-get clean && \
   rm -rf /var/lib/apt/lists/*

# Expose IKE and NAT-T ports
EXPOSE 500 4500