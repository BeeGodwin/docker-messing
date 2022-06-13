# Day 1

https://www.dropbox.com/sh/fsyu7n10mazcda3/AACcWrZ_joHOoMgTCta7TV99a?dl=0

## Getting started
- `docker info` - verifies Docker is installed
- `docker run hello-world` - verifies Docker connects to the internet: pulls and runs a container that just streams a message to stdout.
- `docker run -it ubuntu bash` - runs Ubuntu in a container.
- `docker --version` or `docker version` to get the engine or client version

## Docker Images
- `docker images` list the images in the local registry. Can we keep the image size down?
- `docker ps` to list the running containers 
  - note that they're running a command, and they expose some ports.
  - you can also see the unique container ID and the image it's based off of.

## Run
- `docker run` to (create and) start a container
- use the `-d` switch to detach from the container, and `-it` to run a container interactively. type `exit` to exit.
  - `docker run -it some-container sh` - note the invocation of the shell process at the end (which might be defaulted by the container anyway.)

## Modify
- `docker ps -a` to list containers including exited containers
- `docker commit <containerId> <identifier>` save the modified container as a new image. 
  - Any changes made prior to the commit will show up when the modified image is run.
  - Avoid committing the container with the same name as the image it was created from, or the local registry will go kerflooie.
- `docker diff` to see what changes have been made in a container (i.e. what is in the container that wasn't in the image.)

## Exercise
- Modified a bee-was-here-nginx image to run nginx with a modified index.html. Commit the image.
- `docker run -p 80:80 bee-was-here-nginx nginx -g "daemon off;"`
- then from another window, `curl localhost:80` to hit the nginx url
- now let's store it in docker hub:
  - log in to docker hub, images get repositories made for 'em per image name, namespaced to you if it's an official image
  - we can use markdown format to annotate
  - tag the local image with a remote repository identifier
    - e.g. `docker tag bee-was-here-nginx ayebeecoding/bee-was-here-nginx:latest`
  - log into docker hub
    - e.g. `docker login --username=ayebeecoding` for a password prompt for the local shell (we wouldn't do in production, obvs.)
  - push the image to DH
    - e.g. `docker push ayebeecoding/bee-was-here-nginx:latest`
  - then anyone can `docker run -p 80:80 ayebeecoding/bee-was-here-nginx:latest nginx -g "daemon off;"`

## docker run
- `docker run` creates and starts a new container (we could `docker create` and `docker start` but who cares)
- `docker run [options] <image/tag/imageid> <command> <args>` 
- options;
  - -i interactive
  - -t pseudo-TTY (terminal)
  - -d detached mode (container runs in background, and you interact through ports you've exposed)
  - `docker stop <containerId>` to kill that container afterwards.   
  - from an attached terminal, ctrl-P then ctrl-Q to detach without killing the container process.

## Logging
- Configure a log driver when doing `docker run`
- Read the logs from outside the stopped container with `docker logs <containerId>` to cat stdout for the life of that container.
  - Tail the logs with `docker logs -f <id>`
- Example: 
  - `docker run -d -p 24224:24224 -p 24224:24224/udp --name fluentd -u fluent fluentd` - starts a fluentD container
  - `docker run -d --link fluentd:fluentd --log-driver=fluentd tomcat` - starts a Tomcat instance logging to the fluentD container
  - `docker logs -f <id>` to tail.

# Day 2

## Processes
- Process IDs; process 1 is your main OS process, everything else is a child process.
- Containers run for the duration of their process, so usually they terminate when the process finishes.
- From inside of the container, `kill -9 1` kills the root process of the container. Outside the container, you would kill the OS (if the OS didn't stop you.)
  - This gets handled by namespacing. I don't get a lot of the terminal magic detail about how to prove this out, monitor processes etc.
- Containers can spawn child processes off their internal process id 1.
- Looking at the process tree, there's a containerd abstraction which is the reference implementation of containers. Docker is a shim on top of that.
- Normally we can't see this but if we abuse Docker we can:
  - `docker run -it --privileged --pid=host debian nsenter -t 1 -m -u -n -i sh`
    - a bunch of Debian magic flags and privileges, allows us to run `ps -axfo` or `pstree` etc.

## Port Mapping
- containers are isolated, which is good unless they want to talk to each other.
- Certain services use particular ports through convention. We can map from container to host so that containers can talk to each other.
- Ports are exclusive; no sharing! Binding is 1-1 (port, protocol, process.)
- `80:80` - left is outside, right is inside.
- Mapping a port is not the same as listening to it
- Pass `-P` to docker run to automatically map ports within the ephemeral port range >= 32768 < 61000 (i.e. those that are not allocated by convention)
  - 'cattle not pets' analogy. we want to treat our containers like cattle (hate this analogy) so they are automatic, not tweaked.
    - try and auto-map first, basically. 
  - `docker run -d -P tomcat` auto-maps Tomcat. `docker ps` to see the mapping.
- if you need to specify a port, do `-p <external port>:<internal port>` - but now that port is locked up until that container is killed, and subsequent runs won't work
  - If containers are scaling horizontally, auto-mapping behind a load balancer would be a great WTG.
  - Specific port mapping is probably OK for local development.
  - We build a load balancing setup `docker run -d -p 80:80 --link goofy_golick:goofy_golick --link magical_buck:magical_buck dockercloud/haproxy`

## Images again
- An image is a template for how to create a container.
- Images are build on top of other images, so an image is usually a diff on top of something else.
- We see a unified file system based on a top down view of the image diff stack (all the prior commits.)
  - We can only change the image we're in
  - So if we delete stuff, it's still there.

## Dockerfile
- Dockerfile should be unique within its directory
- We need to use a Dockerfile to get a completely bespoke container
- Dockerfile avoids having to write huge shell commands
- Start with FROM to define a base image to build on (can be `FROM scratch` to start from empty.)
- RUN executes stuff in the container (shell commands, effectively.)
  - Each RUN actually creates a container, executes the command, commits the change, and passes an intermediate image to the next RUN.
  - look at these images with `docker images -a`
  - Aggregate RUN steps with `;/` or `&&` - but why do this? Probably if the steps belong together. We used to chain these commands to get around the hard limit of 256, but that limit is now much higher.
  - Put stuff that changes infrequently near the top of the dockerfile. Stuff that is likely to change goes near the bottom.
- `docker build -t <tag> <path>` usually with a `.` for path.
  - `docker build` is eminently tweakable with many flags & options.
- We need a build context containing all the supporting files needed for the image. 
  - how do we provide the context? context === path.
  - Usually this is the folder we're building in, but not if we're building something remotely- we need to send a build context which is tarred and sent to the process doing the build.
  - Inside the dockerfile, we need to ADD or COPY a file from the build context to the image file system.
  - We can also add a .dockerignore to exclude certain file from the image, using golang excluders / includers

## Commands
- specify a command to the right of docker run, or specify a default command
  - we might inherit this from a base image
  - use the `CMD` instruction (remember it might get overwritten by a command passed at run time)
  - either `CMD echo "Hello, World"` or `CMD ["echo", "Hello, World"]` (exec format)
  - or use the `ENTRYPOINT ["echo"]` to avoid the possibility of overrides (passing the arguments at run time)

## Starting and Stopping
- we might want to manage containers in a particular way 
- we might want to manage containers that are detached
- `docker stop <containerid>`, or `docker kill <containerid>` to circumvent graceful shutdown.
  - app needs to be sigterm aware if it's to clean up gracefully
- `docker start <containerid>` to re-run the command that was originally used to kick it off again
  - start needs to be idempotent, i.e. always predictable results
  - we use `docker logs` in the exercise to prove out that we can re-use containers by replaying stdout
- We can tail the logs, but otherwise, how to interact with a detached container?
  - `docker exec [opts] [container] [command]` to exec in a container.
    - `-d` in detached mode
    - `-it` to interact, as before
    - `--privileged=true` to give extended Linux privileges to command
    - `-u` as user
  - so e.g. `docker start my_container` then `docker exec -it my_container sh`
  - we should not be looking to do this in production, we need to pipe data out of the container if we want to keep it
  - so, can `exec` into a running container and tail the logs of the thing inside it. We do this with a tomcat container.

## Container management
- Images and containers end up taking up (potentially) a lot of space
- So we need to monitor usage and cleanup, on anything but the most evanenscent of environments
- `docker ps` to list containers (with `-a` to include stopped ones)
  - We can manually manage containers this way but who wants that?
  - `docker ps -aq` to get all the container IDs on your system
  - `docker rm` to remove containers (`docker rm $(docker ps -aq)`) - we're evaluating the $() expression
  - `docker rmi` to remove images (`docker rmi $(docker images -aq)`)

## Registries
- When we build we build into the local registry
- As a team we use the Amazon ECR.
- We could also self host a registry with the `registry` image.
  - `docker run -d -p 5001:5000 registry:2`
  - `docker tag ayebeecoding/bee-was-here-nginx localhost:5001/bee-was-here-nginx`
  - `docker push localhost:5001/bee-was-here-nginx`
- We can specify the repo by tagging the repo in the docker tag or docker push
- So, we can specify a repo on `docker run` effectively as a prefix to the image name, or we can tag & push to a registry that's not docker hub

## Volumes
- We can use the machine's file system by mapping bits of it in
- We don't consider the contents of the volume to be part of the image, but we do consider the mount of the volume to be part of the image.
- This can go both ways- make data available to the container, or make space available for the container to write to
- We can also multiplex containers against the same directory (one dir is mounted as a volume in many places.)
- Simple volume - when we only ever need to refer to the volume on container start to sync files in the container with files outside
- Volumes are complex & need use case management to avoid burning disk space with versioning, losing files, or having dangling volumes
- Exercise:
  - Simple volumes
    - Make an nginx container with a simple volume: `docker run -v /someVolume -d nginx`
    - Exec in `docker exec -it <containerId> bash` and observe the volume is there with `ls`
    - Exit container and show the volume exists with `docker inspect <containerId>`
  - Host volumes: they live on the host machine, but docker containers can get at them
    - `docker run -v ${PWD}:/usr/share/nginx/html -p 80:80 -d nginx`
    - Observe custom html served from `${PWD}` in the browser (localhost/path-to-content)
  - Named volumes: when we want a (more or less) persistent pet volume, that doesn't automatically become part of our main file system:
    - `docker volume create --name my_funky_volume`
    - see it with `docker volume ls`
    - `docker run -it -v my_funky_volume:/my_funky_volume busybox sh` to mount the volume in Busybox
    - Try it with and without the -v to prove the volume and the container are separate things and that the container persists
    - Do a `docker volume inspect my_funky_volume` to look at the volume properties
    - `docker volume rm` to remove a volume (or `docker volume rm $(docker volume ls -q)` to remove all volumes)
    - Finding out which volume is in use by which container is less than straightforward.

## More port mapping
- We can always `-P` to automatically map ports
- In the Dockerfile, we can `EXPOSE` ports (as a space separated list, optionally with a protocol) and we should always do so explicitly 
  - as otherwise we don't have a reference port for our container (and everyone needs to remember wtf.)
  - and *some* ports need mapping, otherwise we can't talk to the container
  - The `EXPOSE`d ports are the ones mapped by the `-P` option.
  - I can override the EXPOSE wholly or in part by passing a `-p` option
- Example: 
  - `cd more-port-mapping` and `docker build .` to make the image
  - Pull the image ID out of the last line of log output and do `docker run -it -P <imageId> sh` then ctrl-P, ctrl-Q to detach
  - Finally, `docker ps` to see the port mapping

## Networking
- `docker network ls` - note three inbuilt networks- host, bridge, and null
- Network bindings expire on container stop
- We can pass `--network none` on run to isolate a container from the network 
- We can also pass `--network host` to inherit the host network, as if the host network stack was installed natively.
  - We probably don't need this often but we might if we were e.g. migrating towards a containerised setup.
  - We probably don't want to do this because we are eliminating network isolation between container and host this way.
  - Containers default to the default bridge network, so I get a single network adapter in the `ifconfig`.
  - Containers attached to the bridge network can be reached from wherever the host is reachable.
  - `docker network inspect bridge` to look at the network along with any containers mounted to it.
  - We can restrict containers to only talking to other containers on the bridge by setting to `internal: true`.
  - Containers can reach each other via IP address- but this isn't all that useful
    - We use container linking if we want to establish a reference. 
    - Creating a link add an entry to `/etc/hosts` of the upstream container (the one that depends on the link)
  - Ports are automatically exposed between one container and another within the same (bridge) network (no mapping required.)
  - These have different IP addresses within the bridge network, and we need something like `haproxy` to multiplex them together.
  - We poke as few holes to the outside world as we can get away with.
- We need to add a `--link <outsideId>:<insideId>` to make the other container available to the one that owns the `--link`.
- Example: 
  - `docker run -d --name my-nginx nginx` make a named nginx
  - `docker run -it --link my-nginx:gin busybox sh` link the container into a busybox shell as `gin`
  - `wget gin` to prove we can tap the nginx (thanks to an entry in `/etc/hosts`)
- But we should really use user defined bridge mode, which we get by doing `docker network create <someName>`
  - Why? Because it has a DNS server! 
  - Now if we specify the network we're attached to we can `ping` by container names without having to do an explicit `link`
  - Example: 
    - `docker network create beenet`
    - `docker run -d --network beenet --name nginx1 nginx`
    - `docker run -it --network beenet busybox sh`
    - Then `wget nginx1` from the busybox prompt.
- There's also a user defined overlay mode.

## Docker Compose
- Create and define multi-container Docker applications
- Use a .yml to configure and define your application's services
- You should then be able to do `git pull`, `docker compose build` and `docker compose up` to start, `docker compose down` to tidy up. Bish bosh.
- Try and use the default name as it keeps commands simpler (and you should not need more than one docker-compose.yml per directory)
- Uses a user-defined network populated by the services you declare in the yaml
- https://docs.docker.com/compose/compose-file/compose-file-v3/ for reference
- Exercise:
  - https://github.com/paulhopkins11/microservices-library
  - Build it, then make changes to .yml (like doing a port mapping) and observe that changes are present on `docker compose up`
  - Change one of the things in the image (like the database setup script) and observe that changes are not present until `docker compose build` is done

## Health Checks
- Running containers don't necessarily have healthy applications in them and we might need to modify the state of the containers to suit
  - I.E. scale or cycle containers, based on application state to whatever extent
  - We can already restart if the container crashes (or if the application it's running does)
  - 'Healthy' is defined at the application level, ie you decide
  - health commands will be executed in the container in response to health checks.
  - think about shell commands. so e.g. for a REST app; `curl http://localhost:888/v1/health || exit 1` (get a thing and implicitly return 0, or return 1)
  - Don't use curl though! Make it part of the app so you don't have extra bloat in the image (since you're programming anyway)
  - Health checks need an 
    - interval- can't be too slow or you can't scale, since you rely on healthy instances. 
    - timeout- how long you wait for the health check before deeming failure
    - retries- how many fails we allow before we deem an instance unhealthy.
- in docker run, you can set these up like so:
  - `docker run -d --health-cmd "curl localhost:80 || exit 1" --health-interval=2s --health-timeout=10s --health-retries=3 nginx` 
- but it's better to put the health check in the dockerfile, using the HEALTHCHECK instruction
  - `HEALTHCHECK --interval 5m --timeout=3s --retries=3 CMD <shellcommand> || exit 1`
- and it's even better to put it in the `docker-compose.yml`

## Multi Stage Builds
- A little bit like how CodeBuild vs CodePipeline compares; we can make a pipeline, effectively.
- Avoids us having to build a single container that does All Of The Things
- Allows us to e.g. have the production app run in a container that doesn't contain any non-production dependencies
- We can make anon stages just by using multiple FROM instructions - each FROM adds a build stage starting from that base image.
- We can declare FROM <image> as <outputName> and then use a --from in the next step with the previous name.
- ONBUILD is another useful one- ignored in the base and built in the child. This means we can declare a step as something that happens on all children that use FROM this image- meaning we can compose a predictable build path.
- Add an onbuild to the tag as a courtesy to consumers.

## Wrapup
- We might build outside of Docker then integrate code into a container and push it to a registry. Docker is just a way to package the app with the smallest possible shell.
- we might also do all our building inside Docker, and do something pipeline-y. Perhaps we end up with some cleanup or a bit of a heavyweight container.
- But we could also multi-stage and then this takes care of a lot of cleanup and ensures the lightest possible container actually runs the app.
- Or we could make a build container that spits out the artifact, which runs in a clean container.
- Be deterministic: use specific builds (no :latest etc)
- Don't run as root; dockerfile could have USER node (you have to create first) and chown relevant files.
- Try to avoid having a JVM you don't need, shutdown responsibly
  - JVMs may not be container aware and need resource constraints
- Some tools autogenerate Dockerfiles but they may not be optimal