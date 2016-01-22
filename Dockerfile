FROM litaio/lita

RUN apt-get -qq update

RUN apt-get -y install locales

RUN mkdir -p /usr/src/app
VOLUME ["/usr/src/app"]
WORKDIR /usr/src/app

CMD ["bundle exec lita"]