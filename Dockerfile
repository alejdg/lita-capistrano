FROM litaio/lita

RUN apt-get -qq update

RUN apt-get -y install locales

ENV LANG pt_BR.UTF-8

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
RUN bundle install

VOLUME ["/usr/src/app"]

CMD ["lita"]
