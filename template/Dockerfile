FROM ruby:2.5.1

ENV BUNDLER_VERSION 2.0.2

RUN gem install bundler -v $BUNDLER_VERSION

WORKDIR /usr/src/app

COPY Gemfile .ruby-version ./
RUN bundle install && bundle lock

ENTRYPOINT ["bash"]
