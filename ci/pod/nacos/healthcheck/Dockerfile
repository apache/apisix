FROM alpine:latest

# change workdir to /
WORKDIR /

# install curl
RUN apk --no-cache add bash curl

# add healthcheck script
COPY *.sh /

# add hosted process
CMD ["cat"]
