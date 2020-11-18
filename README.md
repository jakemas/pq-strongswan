# pq-strongswan

Build and run a [strongSwan][STRONGSWAN] 6.0dr Post-Quantum IKEv2 Daemon in a Docker image. The current prototype implementation is based on the two following IETF Internet Drafts:

* [draft-ietf-ipsecme-ikev2-multiple-ke][IKEV2_MULTIPLE_KE]: Multiple Key Exchanges in IKEv2
* [draft-ietf-ipsecme-ikev2-intermediate][IKEV2_INTERMEDIATE]: Intermediate Exchange in the IKEv2 Protocol

[STRONGSWAN]: https://www.strongswan.org
[IKEV2_MULTIPLE_KE]:https://tools.ietf.org/html/draft-ietf-ipsecme-ikev2-multiple-ke
[IKEV2_INTERMEDIATE]:https://tools.ietf.org/html/draft-ietf-ipsecme-ikev2-intermediate

## Prerequisites <a name="section0"></a>

This package and guide is written for ubuntu. All testing was done on an EC2 instance Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0ff4c8fb495a5a50d. 

## Table of Contents

 1. [Docker Setup](#section1)
 2. [strongSwan Configuration](#section2)
 3. [Start up the IKEv2 Daemons](#section3)
 4. [Establish the IKE SA and first Child SA](#section4)
 5. [Establish a second CHILD SA](#section5)
 6. [Use the IPsec Tunnels](#section6)
 7. [Rekeying of first CHILD SA](#section7)
 8. [Rekeying of second CHILD SA](#section8)
 9. [Rekeying of IKE SA](#section9)
10. [SA Status after Rekeying](#section10)


## Docker Setup <a name="section1"></a>

### Install Docker

See Docker installation guide https://docs.docker.com/engine/install/ubuntu/.

Update the apt package index and install packages to allow apt to use a repository over HTTPS:

```console
$ sudo apt-get update
$ sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
```
Add Docker’s official GPG key:

```console
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
```

Use the following command to set up the stable repository:

```console
$ sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
```

Install Docker engine:

```console
$ sudo apt-get update
$ sudo apt-get install docker-ce docker-ce-cli containerd.io
```

### Install docker-compose

See docker-compose installation guide https://docs.docker.com/compose/install/.

Download the current stable release of Docker Compose:

```console
$ sudo curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
```
Apply executable permissions to the binary:

```console
$ sudo chmod +x /usr/local/bin/docker-compose
```

### Pull Docker Image

```console
$ git clone https://github.com/jakemas/pq-strongswan.git
```
### Build Docker Image

```console
$ cd docker/pq-strongswan
$ docker build --tag pq-strongswan:6.0dr2 .
```

(TODO: build this on dockerhub and just let it be a download - this will reduce build time)

### Create Docker Containers and Local Networks

We now use `docker-compose` to bring the `moon` and `carol` docker containers up:

```console
$ sh scripts/gen_dirs.sh
$ docker-compose up
Creating moon ... done
Creating carol ... done
Attaching to moon, carol
```

The network topology that has been created looks as follows:
```
               +-------+                        +--------+
  10.3.0.1 --- | carol | === 192.168.0.0/24 === |  moon  | --- 10.1.0.0/16
 Virtual IP    +-------+ .3     Internet     .2 +--------+ .2    Intranet
```

VPN client `carol` and VPN gateway `moon` are connected with each other via the `192.168.0.0/24` network emulating the `Internet`. Behind `moon` there is an additional `10.1.0.0/16` network acting as an `Intranet`. Within the IPsec tunnel `carol` is going to use the virtual IP address `10.3.0.1` that will be assigned to the client by the gateway via the IKEv2 protocol.

## strongSwan Configuration <a name="section2"></a>

strongSwan options can be configured in the `/etc/strongswan.conf` file which in our case contains the startup scripts and a logging directive diverting the debug output to `stderr`. We also define the size of the IP fragments and the maximum IKEv2 packet size which can be quite considerable with some post-quantum Key Exchange Methods.
```console
charon {
   filelog {
      stderr {
         default = 1
      }
   }
   send_vendor_id = yes
   fragment_size = 1480
   max_packet = 30000
}


swanctl {
  load = pem pkcs1 x509 revocation constraints pubkey openssl random
}
charon-systemd {
  load = random nonce aes sha1 sha2 hmac pem pkcs1 x509 revocation curve25519  curl kernel-netlink socket-default updown v>
}
```
### NIST Round 3 Submission KEM Candidates

| Keyword  | Key Exchange Method | Keyword  | Key Exchange Method | Keyword  | Key Exchange Method |
| :------- | :------------------ | :------- | :------------------ | :------- | :------------------ |
| `kyber1` | `KYBER_L1`          | `kyber3` | `KYBER_L3`       | `kyber5` | `KYBER_L5`       |
| `ntrup1` | `NTRU_HPS_L1`       | `ntrup3` | `NTRU_HPS_L3`    | `ntrup5` | `NTRU_HPS_L5`    |
|          |                     | `ntrur3` | `NTRU_HRSS_L3`   |          |                     |
| `saber1` | `SABER_L1`       | `saber3` | `SABER_L3`       | `saber5` | `SABER_L5`       |


### NIST Alternate KEM Candidates

| Keyword   | Key Exchange Method | Keyword   | Key Exchange Method | Keyword   | Key Exchange Method |
| :-------- | :------------------ | :-------- | :------------------ | :-------- | :------------------ |
| `frodoa1` | `FRODO_AES_L1`   | `frodoa3` | `FRODO_AES_L3`   | `frodoa5` | `FRODO_AES_L5`   |
| `frodos1` | `FRODO_SHAKE_L1` | `frodos3` | `FRODO_SHAKE_L3` | `frodos5` | `FRODO_SHAKE_L5` |
| `sike1`   | `SIKE_L1`        | `sike3`   | `SIKE_L3`        | `sike5`   | `SIKE_L5`        |
|           |                     | `sike2`   | `SIKE_L2`        |           |                     |

The KEM algorithms listed above are implemented by the strongSwan `oqs` plugin which in turn uses the  [liboqs][LIBOQS]  Open Quantum-Safe library. There is also a `frodo` plugin which implements the `FrodoKEM` algorithm with strongSwan crypto primitives. There is currently no support for the `BIKE` and  `HQC` alternate KEM candidates. `Classic McEliece` , although being a NIST round 3 submission KEM candidate, is not an option for IKE due to the huge public key size of more than 100 kB.

[LIBOQS]: https://github.com/open-quantum-safe/liboqs

### VPN Client Configuration

This is the `ipsec.conf` connection configuration file of the client `carol`:

```console
config setup
  strictcrlpolicy=no
  charondebug=all
conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev2
  authby=secret
  mobike=no
conn net-net
  auto=add
  leftfirewall=yes
  left=192.168.0.3
  leftid=192.168.0.3
  leftsubnet=10.3.0.0/16
  leftauth=psk
  right=192.168.0.2
  rightsubnet=10.1.0.0/16
  rightauth=psk
  ike=aes256gcm16-sha512-x25519-ke1_kyber3
  esp=aes256gcm16-sha512-x25519-ke1_kyber3
```

The child security association `net-net` is defined. It connects the client with the outer IP address of the gateway.

### VPN Gateway Configuration

This is the `ipsec.conf` connection configuration file of the gateway `moon`:

```console
config setup
  strictcrlpolicy=no
  charondebug=all
conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev2
  authby=secret
  mobike=no
conn net-net
  auto=add
  leftfirewall=yes
  left=192.168.0.2
  leftid=192.168.0.2
  leftsubnet=10.1.0.0/16
  leftauth=psk
  right=192.168.0.3
  rightsubnet=10.3.0.0/16
  rightauth=psk
  ike=aes256gcm16-sha512-x25519-ke1_kyber3
  esp=aes256gcm16-sha512-x25519-ke1_kyber3
```






6) In a new terminal window, connect to the moon image and start ipsec:
docker exec -ti moon /bin/bash
ipsec start

7) In a new terminal window, connect to the carol image and start ipsec:
docker exec -ti carol /bin/bash
ipsec start

you should see

moon     | bash-5.0# ipsec_starter[12]: Starting strongSwan 6.0dr2 IPsec [starter]...
moon     | 
moon     | ipsec_starter[15]: charon (16) started after 20 ms
moon     | 
carol    | bash-5.0# ipsec_starter[12]: Starting strongSwan 6.0dr2 IPsec [starter]...
carol    | 
carol    | ipsec_starter[15]: charon (16) started after 20 ms
carol    | 

see the ipsec connection with:
ipsec statusall

Status of IKE charon daemon (strongSwan 6.0dr2, Linux 5.4.0-1029-aws, x86_64):
  uptime: 22 seconds, since Nov 18 17:24:26 2020
  malloc: sbrk 1216512, mmap 0, used 329104, free 887408
  worker threads: 11 of 16 idle, 5/0/0/0 working, job queue: 0/0/0/0, scheduled: 0
  loaded plugins: charon aes des rc2 sha2 sha1 md5 mgf1 random nonce x509 revocation constraints pubkey pkcs1 pkcs7 pkcs8 pkcs12 pgp dnskey sshkey pem fips-prf gmp curve25519 xcbc cmac hmac gcm ntru oqs drbg attr kernel-netlink resolve socket-default stroke vici updown xauth-generic counters
Listening IP addresses:
  192.168.0.3
Connections:
     net-net:  192.168.0.3...192.168.0.2  IKEv2
     net-net:   local:  [192.168.0.3] uses pre-shared key authentication
     net-net:   remote: [192.168.0.2] uses pre-shared key authentication
     net-net:   child:  10.3.0.0/16 === 10.1.0.0/16 TUNNEL
Security Associations (0 up, 0 connecting):
  none

8) On carol, (client) start the child SA:
swanctl --initiate --child net-net

[IKE] initiating IKE_SA net-net[1] to 192.168.0.2
[ENC] generating IKE_SA_INIT request 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(REDIR_SUP) N(IKE_INT_SUP) V ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (724 bytes)
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (276 bytes)
[ENC] parsed IKE_SA_INIT response 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(CHDLESS_SUP) N(IKE_INT_SUP) N(MULT_AUTH) V ]
[IKE] received strongSwan vendor ID
[CFG] selected proposal: IKE:AES_GCM_16_256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
[ENC] generating IKE_INTERMEDIATE request 1 [ KE ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (1249 bytes)
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (1153 bytes)
[ENC] parsed IKE_INTERMEDIATE response 1 [ KE ]
[IKE] authentication of '192.168.0.3' (myself) with pre-shared key
[IKE] establishing CHILD_SA net-net{1}
[ENC] generating IKE_AUTH request 2 [ IDi N(INIT_CONTACT) IDr AUTH SA TSi TSr N(MULT_AUTH) N(EAP_ONLY) N(MSG_ID_SYN_SUP) ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (413 bytes)
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (237 bytes)
[ENC] parsed IKE_AUTH response 2 [ IDr AUTH SA TSi TSr N(AUTH_LFT) ]
[IKE] authentication of '192.168.0.2' with pre-shared key successful
[IKE] IKE_SA net-net[1] established between 192.168.0.3[192.168.0.3]...192.168.0.2[192.168.0.2]
[IKE] scheduling reauthentication in 3301s
[IKE] maximum IKE_SA lifetime 3481s
[CFG] selected proposal: ESP:AES_GCM_16_256/NO_EXT_SEQ
[IKE] CHILD_SA net-net{1} established with SPIs c52002b6_i c8c6b208_o and TS 10.3.0.0/16 === 10.1.0.0/16
[CHD] updown: /usr/libexec/ipsec/_updown: 310: iptables: not found
[CHD] updown: /usr/libexec/ipsec/_updown: 313: iptables: not found
[IKE] received AUTH_LIFETIME of 3314s, scheduling reauthentication in 3134s
initiate completed successfully

ipsec statusall

Status of IKE charon daemon (strongSwan 6.0dr2, Linux 5.4.0-1029-aws, x86_64):
  uptime: 2 minutes, since Nov 18 17:24:27 2020
  malloc: sbrk 2433024, mmap 0, used 440960, free 1992064
  worker threads: 11 of 16 idle, 5/0/0/0 working, job queue: 0/0/0/0, scheduled: 3
  loaded plugins: charon aes des rc2 sha2 sha1 md5 mgf1 random nonce x509 revocation constraints pubkey pkcs1 pkcs7 pkcs8 pkcs12 pgp dnskey sshkey pem fips-prf gmp curve25519 xcbc cmac hmac gcm ntru oqs drbg attr kernel-netlink resolve socket-default stroke vici updown xauth-generic counters
Listening IP addresses:
  192.168.0.3
Connections:
     net-net:  192.168.0.3...192.168.0.2  IKEv2
     net-net:   local:  [192.168.0.3] uses pre-shared key authentication
     net-net:   remote: [192.168.0.2] uses pre-shared key authentication
     net-net:   child:  10.3.0.0/16 === 10.1.0.0/16 TUNNEL
Security Associations (1 up, 0 connecting):
     net-net[1]: ESTABLISHED 86 seconds ago, 192.168.0.3[192.168.0.3]...192.168.0.2[192.168.0.2]
     net-net[1]: IKEv2 SPIs: 22ecdebbe976b188_i* 3d9763960d3517d6_r, pre-shared key reauthentication in 50 minutes
     net-net[1]: IKE proposal: AES_GCM_16_256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
     net-net{1}:  INSTALLED, TUNNEL, reqid 1, ESP SPIs: c52002b6_i c8c6b208_o
     net-net{1}:  AES_GCM_16_256, 0 bytes_i, 0 bytes_o, rekeying in 14 minutes
     net-net{1}:   10.3.0.0/16 === 10.1.0.0/16

## Use the IPsec Tunnels <a name="section6"></a>

We ping the gateway `moon` on its external IP address itself
```console
carol# ping -c 1 192.168.0.2
PING 192.168.0.2 (192.168.0.2) 56(84) bytes of data.
64 bytes from 192.168.0.2: icmp_seq=1 ttl=64 time=0.293 ms
```






