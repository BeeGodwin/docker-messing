FROM alpine
RUN echo "<h1>hello world</h1>" >> index.html


FROM nginx
COPY --from=0 /index.html usr/share/nginx/html/index.html
