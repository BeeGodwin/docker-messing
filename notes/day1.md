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