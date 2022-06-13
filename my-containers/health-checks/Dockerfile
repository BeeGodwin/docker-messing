FROM nginx

RUN apt-get update; apt-get install curl

HEALTHCHECK --interval=2s --timeout=10s --retries=3 CMD curl localhost || exit 1