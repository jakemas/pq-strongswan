# pq-strongswan

Build and run a [strongSwan][STRONGSWAN] 6.0dr Post-Quantum IKEv2 Daemon in a Docker image. The current prototype implementation is based on the two following IETF Internet Drafts:

* [draft-ietf-ipsecme-ikev2-multiple-ke][IKEV2_MULTIPLE_KE]: Multiple Key Exchanges in IKEv2
* [draft-ietf-ipsecme-ikev2-intermediate][IKEV2_INTERMEDIATE]: Intermediate Exchange in the IKEv2 Protocol

## Branches
There are two branches in this repo, they both represent different network architecture:
- The `site-to-site` (and thus also `main`) branch represents a site-to-site VPN connection. A site-to-site VPN is a connection between two or more networks, such as a corporate network and a branch office network. 
- The `road-warrior` branch represents a Road Warrior - VPN gateway connection. Road Warriors are remote users who want to connect to a network. This example is a combination of the [docker image built to showcase PQ strongSwan][PQ-STRONGSWAN] by Andreas Steffen, and the strongSwan configuration example [rw-ntru-psk][RW-NTRU-PSK].

There is more detail in this readme about the particular network configuration of the branch.

[STRONGSWAN]: https://www.strongswan.org
[IKEV2_MULTIPLE_KE]:https://tools.ietf.org/html/draft-ietf-ipsecme-ikev2-multiple-ke
[IKEV2_INTERMEDIATE]:https://tools.ietf.org/html/draft-ietf-ipsecme-ikev2-intermediate
[PQ-STRONGSWAN]:https://github.com/strongX509/docker/tree/master/pq-strongswan
[RW-NTRU-PSK]:https://github.com/strongswan/strongswan/tree/master/testing/tests/ikev2/rw-ntru-psk

## Prerequisites <a name="section0"></a>

This package and guide is written for ubuntu. All testing was done on an EC2 instance Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - ami-0ff4c8fb495a5a50d. A t2-medium instance with 8Gb of storage works just fine.

## Table of Contents

 1. [Docker Setup](#section1)
 2. [strongSwan Configuration](#section2)
 3. [Start up the IKEv2 Daemons](#section3)
 4. [Establish the IKE SA and first Child SA](#section4)
 5. [Use the IPsec Tunnels](#section6)
 6. [Rekeying of first CHILD SA](#section7)
 7. [Rekeying of IKE SA](#section9)
 8. [SA Status after Rekeying](#section10)


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
$ cd pq-strongswan
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
As we will have multiple terminal windows open for each client, we shall refer to this window as `terminal-monitor`.

The network topology that has been created looks as follows:
```
               +-------+                        +--------+
  10.3.0.1 --- | carol | === 192.168.0.0/24 === |  moon  | --- 10.1.0.2
 Virtual IP .3 +-------+ .3     Internet     .2 +--------+ .2  Virtual IP
```

VPN client `carol` and VPN gateway `moon` are connected with each other via the `192.168.0.0/24` network emulating the `Internet`. Within the IPsec tunnel `carol` is going to use the virtual IP address `10.3.0.3` that will be assigned to the client by the gateway via the IKEv2 protocol.

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

conn %default
        ikelifetime=60m
        lifetime=20m
        rekeymargin=3m
        keyingtries=1
        keyexchange=ikev2
        ike=aes256gcm16-sha512-x25519-ke1_kyber3
        esp=aes256gcm16-sha512-x25519-ke1_kyber3
        authby=psk

conn Tunnel1
        left=192.168.0.3
        leftid=carol.strongswan.org
        leftsubnet=10.3.0.1/16
        right=192.168.0.2
        rightsubnet=10.1.0.0/16
        rightid=moon.strongswan.org
        auto=add
```

The child security association `Tunnel1` is defined. It connects the client with the IP address of the gateway `192.168.0.2`. We choose to use 
`aes256gcm16-sha512-x25519-ke1_kyber3` as our cipher suite. A full list of cipher suites and keywords for their use can be found at [strongSwan IKEv2 Cipher Suites][IKEV2-CS]. The choice `aes256gcm16-sha512-x25519-ke1_kyber3`uses:
- Encryption Algorithm `aes256gcm16`: 256 bit AES-CCM with 128 bit ICV.
- Integrity Algorithm `sha512`: SHA2_512_256 HMAC.
- Key Exchange Algorithm `x25519`: Elliptic Curve Diffie-Hellman with 256 bit Elliptic Curve25519.
- Key Exchange Algorithm `ke1_kyber3`: Kyber Level 3 (At least as hard to break as AES192 - 96 bit quantum security).

Other NIST round 3 submission candidates can be tested, using their respective keyword from the table provided above. The [draft-ietf-ipsecme-ikev2-multiple-ke][IKEV2_MULTIPLE_KE] also facilitates the use of more than two key exchanges, for example:
```console
aes256gcm16-sha512-x25519-ke1_kyber3-ke2_ntrup3-ke3_saber3
```
will negotiate a *hybrid* key exchange that will use `X25519` elliptic curve for the initial exchange, followed by three rounds of post-quantum key exchanges consisting of the `Kyber`, `NTRU` and `Saber` algorithms, all of them on NIST security level 3. 

[IKEV2-CS]:https://wiki.strongswan.org/projects/strongswan/wiki/IKEv2CipherSuites

### VPN Gateway Configuration

This is the `ipsec.conf` connection configuration file of the gateway `moon`:

```console
config setup

conn %default
        ikelifetime=60m
        lifetime=20m
        rekeymargin=3m
        keyingtries=1
        keyexchange=ikev2
        ike=aes256gcm16-sha512-x25519-ke1_kyber3
        esp=aes256gcm16-sha512-x25519-ke1_kyber3
        authby=psk

conn Tunnel1
        left=192.168.0.2
        leftsubnet=10.1.0.0/16
        leftid=moon.strongswan.org
        right=192.168.0.3
        rightsubnet=10.3.0.0/16
        rightid=carol.strongswan.org
        auto=add
```

## Start up the IKEv2 Daemons <a name="section3"></a>

### On VPN Gateway "moon"

In an additional console window we refer to as `terminal-moon` we open a `bash` shell to start and manage the strongSwan daemon in the `moon` container:

```console
$ docker exec -ti moon /bin/bash
$ ipsec start
Starting strongSwan 6.0dr2 IPsec [starter]...
```
Back in the terminal from which we started the docker image `terminal-monitor`, we now see an update:

```console
Starting moon ... done
Starting carol ... done
Attaching to moon, carol
moon     | bash-5.0# ipsec_starter[12]: Starting strongSwan 6.0dr2 IPsec [starter]...
moon     | 
moon     | ipsec_starter[15]: charon (16) started after 20 ms
moon     | 
```

### On VPN Client "carol"

In an additional console window we refer to as `terminal-carol` we open a `bash` shell to start and manage the strongSwan daemon in the `carol` container:

```console
$ docker exec -ti carol /bin/bash
$ ipsec start
Starting strongSwan 6.0dr2 IPsec [starter]...
```
Back in the terminal from which we started the docker image `terminal-monitor`, we now see a second update:

```console
Starting moon ... done
Starting carol ... done
Attaching to moon, carol
moon     | bash-5.0# ipsec_starter[12]: Starting strongSwan 6.0dr2 IPsec [starter]...
moon     | 
moon     | ipsec_starter[15]: charon (16) started after 20 ms
moon     | 
carol    | bash-5.0# ipsec_starter[14]: Starting strongSwan 6.0dr2 IPsec [starter]...
carol    | 
carol    | ipsec_starter[17]: charon (18) started after 20 ms
carol    | 
```
We can see the status of the connection with `ipsec status`

```console
carol# ipsec statusall
Status of IKE charon daemon (strongSwan 6.0dr2, Linux 5.4.0-1029-aws, x86_64):
  uptime: 99 seconds, since Nov 19 12:59:35 2020
  malloc: sbrk 1351680, mmap 0, used 333888, free 1017792
  worker threads: 11 of 16 idle, 5/0/0/0 working, job queue: 0/0/0/0, scheduled: 0
  loaded plugins: charon aes des rc2 sha2 sha1 md5 mgf1 random nonce x509 revocation constraints pubkey pkcs1 pkcs7 pkcs8 pkcs12 pgp dnskey sshkey pem fips-prf gmp curve25519 xcbc cmac hmac gcm ntru oqs drbg attr kernel-netlink resolve socket-default stroke vici updown xauth-generic counters
Listening IP addresses:
  192.168.0.3
Connections:
     Tunnel1:  192.168.0.3...192.168.0.2  IKEv2
     Tunnel1:   local:  [carol.strongswan.org] uses pre-shared key authentication
     Tunnel1:   remote: [moon.strongswan.org] uses pre-shared key authentication
     Tunnel1:   child:  10.3.0.0/16 === 10.1.0.0/16 TUNNEL
Security Associations (0 up, 0 connecting):
  none
```
Similarly, this can be done with the `swanctl --list-conns` command:

```console
carol# swanctl --list-conns
Tunnel1: IKEv2, reauthentication every 3420s, no rekeying
  local:  192.168.0.3
  remote: 192.168.0.2
  local pre-shared key authentication:
    id: carol.strongswan.org
  remote pre-shared key authentication:
    id: moon.strongswan.org
  Tunnel1: TUNNEL, rekeying every 1020s
    local:  10.3.0.0/16
    remote: 10.1.0.0/16
```
## Establish the IKE SA and first Child SA <a name="section4"></a>

For IKEv2, the Security Association (SA) that carries IKE messages is referred to as the IKE SA, and the SAs for the Encapsulating Security Payload (ESP) and Authentication Header (AH) are child SAs. We do this using `ipsec up Tunnel1`, however this can also be done using `swanctl --initiate --child Tunnel1`.
```console
carol# ipsec up Tunnel1
[IKE] initiating IKE_SA Tunnel1[1] to 192.168.0.2
[ENC] generating IKE_SA_INIT request 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(REDIR_SUP) N(IKE_INT_SUP) V ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (724 bytes)
```
We see that client `carol` sends the `IKEV2_FRAGMENTATION_SUPPORTED` (`FRAG_SUP`) and `INTERMEDIATE_EXCHANGE_SUPPORTED` (`IKE_INT_SUP`) notifications in the `IKE_SA_INIT` request, for the two mechanisms required to enable a post-quantum key exchange.

Also a traditional `KEY_EXCHANGE` (`KE`) payload is sent which contains the public factor of the legacy `X25519` elliptic curve Diffie-Hellman group.
```console
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (276 bytes)
[ENC] parsed IKE_SA_INIT response 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(CHDLESS_SUP) N(IKE_INT_SUP) N(MULT_AUTH) V ]
```

Gateway `moon` supports the same mechanisms so that a post-quantum key exchange should succeed and its `KE` payload in turn allows to form a first `SKEYSEED` master secret that is used  to derive IKEv2 encryption and data integrity session keys so that the subsequent `IKE_INTERMEDIATE` messages in a secure way.
```console
[IKE] received strongSwan vendor ID
[CFG] selected proposal: IKE:AES_GCM_16_256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
```
The negotiated *hybrid* key exchange will use the `X25519` elliptic curve for the initial exchange, followed by a post-quantum key exchange consisting of the `Kyber` algorithm on NIST security level 3. 
```console
[ENC] generating IKE_INTERMEDIATE request 1 [ KE ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (1249 bytes)
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (1153 bytes)
[ENC] parsed IKE_INTERMEDIATE response 1 [ KE ]
```
The `KYBER_L3` key exchange defined as `ADDITIONAL_KEY_EXCHANGE_1`has been completed and the derived secret has been added to the `SKEYSEED` master secret.
```console
[IKE] authentication of '192.168.0.3' (myself) with pre-shared key
[IKE] establishing CHILD_SA Tunnel1{1}
[ENC] generating IKE_AUTH request 2 [ IDi N(INIT_CONTACT) IDr AUTH SA TSi TSr N(MULT_AUTH) N(EAP_ONLY) N(MSG_ID_SYN_SUP) ]
[NET] sending packet: from 192.168.0.3[500] to 192.168.0.2[500] (413 bytes)
[NET] received packet: from 192.168.0.2[500] to 192.168.0.3[500] (237 bytes)
[ENC] parsed IKE_AUTH response 2 [ IDr AUTH SA TSi TSr N(AUTH_LFT) ]
[IKE] authentication of '192.168.0.2' with pre-shared key successful
[IKE] IKE_SA Tunnel1[1] established between 192.168.0.3[carol.strongswan.org]...192.168.0.2[moon.strongswan.org]
[IKE] scheduling reauthentication in 3268s
[IKE] maximum IKE_SA lifetime 3448s
[CFG] selected proposal: ESP:AES_GCM_16_256/NO_EXT_SEQ
[IKE] CHILD_SA Tunnel1{1} established with SPIs cb7bdaa5_i c9c43a36_o and TS 10.3.0.0/16 === 10.1.0.0/16
[IKE] received AUTH_LIFETIME of 3377s, scheduling reauthentication in 3197s
initiate completed successfully
```

## Use the IPsec Tunnels <a name="section6"></a>
First we ping the network behind gateway `moon`
```console
carol# ping -c 2 10.1.0.2
PING 10.1.0.2 (10.1.0.2) 56(84) bytes of data.
64 bytes from 10.1.0.2: icmp_seq=1 ttl=64 time=0.104 ms
64 bytes from 10.1.0.2: icmp_seq=2 ttl=64 time=0.114 ms

--- 10.1.0.2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1017ms
rtt min/avg/max/mdev = 0.104/0.109/0.114/0.005 ms
```
and then the gateway `moon` on its external IP address itself
```console
carol# ping -c 1 192.168.0.2
PING 192.168.0.2 (192.168.0.2) 56(84) bytes of data.
64 bytes from 192.168.0.2: icmp_seq=1 ttl=64 time=0.063 ms

--- 192.168.0.2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.063/0.063/0.063/0.000 ms
```
Now let's have a look at the established tunnel connections:

```console
$carol# swanctl --list-sas
Tunnel1: #1, ESTABLISHED, IKEv2, 739acec0ff8f1f84_i* 5de2e8d07fa3cec2_r
  local  'carol@strongswan.org' @ 192.168.0.3[4500]
  remote 'moon.strongswan.org' @ 192.168.0.2[4500]
  AES_GCM_16-256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
  established 446s ago, reauth in 2669s
  Tunnel1: #1, reqid 1, INSTALLED, TUNNEL, ESP:AES_GCM_16-256
    installed 447s ago, rekeying in 496s, expires in 754s
    in  c2f347ac,    168 bytes,     2 packets,   152s ago
    out c55a612d,    168 bytes,     2 packets,   152s ago
    local  10.3.0.1/32
    remote 10.1.0.0/16
```

## Rekeying of first CHILD SA <a name="section7"></a>

The rekeying of the first 'CHILD_SA' takes place automatically after the `lifetime` interval of `20` minutes.
We can however force this update with the `swanctl --rekey --child Tunnel1` command.

First, in order to capture the log of the rekey, we must open a new terminal window to monitor Carol's connection.
We call this terminal window `terminal-carol-log`. To start the log, we use `swanctl --log`.
```console
$ docker exec -ti carol /bin/bash
$ swanctl --log
```

Now, back in `terminal-carol` we can initiate the rekey:
```console
carol# swanctl --rekey --child Tunnel1
rekey completed successfully
```
In terminal window `terminal-carol-log` we now see the rekey:
```console
09[CFG] vici rekey CHILD_SA 'Tunnel1'
14[IKE] establishing CHILD_SA Tunnel1{3} reqid 1
14[ENC] generating CREATE_CHILD_SA request 6 [ N(REKEY_SA) SA No KE TSi TSr ]
14[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (389 bytes)
09[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (242 bytes)
09[ENC] parsed CREATE_CHILD_SA response 6 [ SA No KE TSi TSr N(ADD_KE) ]
```
```console
09[CFG] selected proposal: ESP:AES_GCM_16_256/CURVE_25519/NO_EXT_SEQ/KE1_KYBER_L3
```
The second KE for the Kyber key now takes place:
```console
09[ENC] generating IKE_FOLLOWUP_KE request 7 [ KE N(ADD_KE) ]
09[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (1258 bytes)
06[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (1153 bytes)
06[ENC] parsed IKE_FOLLOWUP_KE response 7 [ KE ]
```
```console
06[IKE] inbound CHILD_SA Tunnel1{3} established with SPIs c26b805c_i cf0b9b25_o and TS 10.3.0.0/16 === 10.1.0.0/16
06[IKE] outbound CHILD_SA Tunnel1{3} established with SPIs c26b805c_i cf0b9b25_o and TS 10.3.0.0/16 === 10.1.0.0/16
```
The new `CHILD_SA` has been established..
```console
06[IKE] closing CHILD_SA Tunnel1{2} with SPIs c8c40c81_i (0 bytes) c2bbffb8_o (0 bytes) and TS 10.3.0.0/16 === 10.1.0.0/16
06[IKE] sending DELETE for ESP CHILD_SA with SPI c8c40c81
06[ENC] generating INFORMATIONAL request 8 [ D ]
06[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (69 bytes)
07[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (69 bytes)
07[ENC] parsed INFORMATIONAL response 8 [ D ]
07[IKE] received DELETE for ESP CHILD_SA with SPI c2bbffb8
07[IKE] CHILD_SA closed
```
The old `CHILD_SA` has been deleted.

## Rekeying of IKE SA <a name="section9"></a>

The rekeying of the first 'IKE_SA' takes place automatically after the `rekey_time` interval of `30` minutes.
Again, however, we can force this rekey using the command `swanctl --rekey --ike Tunnel1`.

In `terminal-carol` we eneter the command:

```console
carol# swanctl --rekey --ike Tunnel1
rekey completed successfully
```

In terminal window `terminal-carol-log` we now see the rekey:
```console
14[CFG] vici rekey IKE_SA 'Tunnel1'
14[IKE] initiating IKE_SA Tunnel1[2] to 192.168.0.2
14[ENC] generating CREATE_CHILD_SA request 3 [ SA No KE ]
14[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (661 bytes)
12[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (198 bytes)
12[ENC] parsed CREATE_CHILD_SA response 3 [ SA No KE N(ADD_KE) ]
```
```console
12[CFG] selected proposal: IKE:AES_GCM_16_256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
```
The second KE for the Kyber key now takes place:
```console
12[ENC] generating IKE_FOLLOWUP_KE request 4 [ KE N(ADD_KE) ]
12[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (1258 bytes)
08[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (1153 bytes)
08[ENC] parsed IKE_FOLLOWUP_KE response 4 [ KE ]
```

```console
08[IKE] scheduling reauthentication in 3268s
08[IKE] maximum IKE_SA lifetime 3448s
08[IKE] IKE_SA Tunnel1[2] rekeyed between 192.168.0.3[carol.strongswan.org]...192.168.0.2[moon.strongswan.org]
```
The new `IKE_SA` has been established.
```console
08[IKE] deleting IKE_SA Tunnel1[1] between 192.168.0.3[carol.strongswan.org]...192.168.0.2[moon.strongswan.org]
08[IKE] sending DELETE for IKE_SA Tunnel1[1]
08[ENC] generating INFORMATIONAL request 5 [ D ]
08[NET] sending packet: from 192.168.0.3[4500] to 192.168.0.2[4500] (65 bytes)
08[NET] received packet: from 192.168.0.2[4500] to 192.168.0.3[4500] (57 bytes)
08[ENC] parsed INFORMATIONAL response 5 [ ]
08[IKE] IKE_SA deleted

```
The old `IKE_SA` has been deleted.

## SA Status after Rekeying <a name="section10"></a>
If you're quick you can catch the deleted tunnel with a `swanctl --list-sas` command:
```console
carol# swanctl --list-sas
Tunnel1: #3, ESTABLISHED, IKEv2, 769fedc951c1db8e_i* 7080ece2954ba603_r
  local  'carol.strongswan.org' @ 192.168.0.3[4500]
  remote 'moon.strongswan.org' @ 192.168.0.2[4500]
  AES_GCM_16-256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
  established 14s ago, reauth in 2623s
  Tunnel1: #1, reqid 1, DELETED, TUNNEL, ESP:AES_GCM_16-256
    installed 518s ago, rekeying in 363s, expires in 682s
    in  c6eacaae,    168 bytes,     2 packets,    20s ago
    out cb43bc91,    168 bytes,     2 packets,    20s ago
    local  10.3.0.0/16
    remote 10.1.0.0/16
  Tunnel1: #2, reqid 1, INSTALLED, TUNNEL, ESP:AES_GCM_16-256/CURVE_25519/KE1_KYBER_L3
    installed 1s ago, rekeying in 883s, expires in 1199s
    in  c74c941d,      0 bytes,     0 packets
    out c9cb9458,      0 bytes,     0 packets
    local  10.3.0.0/16
    remote 10.1.0.0/16
```
Otherwise you will just see:

```console
carol# swanctl --list-sas
Tunnel1: #3, ESTABLISHED, IKEv2, 769fedc951c1db8e_i* 7080ece2954ba603_r
  local  'carol.strongswan.org' @ 192.168.0.3[4500]
  remote 'moon.strongswan.org' @ 192.168.0.2[4500]
  AES_GCM_16-256/PRF_HMAC_SHA2_512/CURVE_25519/KE1_KYBER_L3
  established 31s ago, reauth in 2606s
  Tunnel1: #2, reqid 1, INSTALLED, TUNNEL, ESP:AES_GCM_16-256/CURVE_25519/KE1_KYBER_L3
    installed 18s ago, rekeying in 866s, expires in 1182s
    in  c74c941d,      0 bytes,     0 packets
    out c9cb9458,      0 bytes,     0 packets
    local  10.3.0.0/16
    remote 10.1.0.0/16
```
