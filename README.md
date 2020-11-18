# pq-strongswan
Docker Image for testing pq-strongswan

## Docker Setup <a name="section1"></a>

### Create Docker Containers and Local Networks

We clone the strongSwan `docker-compose` environment which automatically installs the `strongx509/pq-strongswan` docker image and brings the `moon` and `carol` docker containers up:
```console
$ git clone https://github.com/jakemas/pq-strongswan.git
$ cd docker/pq-strongswan
$ sh scripts/gen_dirs.sh
$ docker-compose up
Creating moon ... done
Creating carol ... done
Attaching to moon, carol
```
