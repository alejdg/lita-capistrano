FROM litaio/lita

RUN apt-get -qq update

RUN apt-get -y install locales

COPY locale /etc/default/locale
RUN locale-gen pt_BR.UTF-8 &&\
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales

RUN mkdir -p /usr/src/app
COPY Gemfile /usr/src/app
COPY Gemfile.lock /usr/src/app
WORKDIR /usr/src/app
RUN bundle install

VOLUME ["/usr/src/app"]

CMD ["lita"]
