FROM ubuntu

# Install Test::Nginx
RUN apt update
RUN apt install -y cpanminus make
RUN cpanm --notest Test::Nginx

RUN apt install -y sudo git gawk curl

WORKDIR /apisix

ENV PERL5LIB=.:$PERL5LIB

ENTRYPOINT ["tail", "-f", "/dev/null"]
