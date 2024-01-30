FROM ubuntu:20.04

# Install Test::Nginx
RUN apt update
RUN apt install -y cpanminus make
RUN cpanm --notest Test::Nginx

RUN apt install -y sudo git

WORKDIR /apisix

ENTRYPOINT ["tail", "-f", "/dev/null"]
