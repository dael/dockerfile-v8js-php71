FROM php:7.1-fpm

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends locales

ENV COMPOSER_ALLOW_SUPERUSER 1

RUN echo "Asia/Seoul" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# ko_KR.UTF-8 UTF-8/ko_KR.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="ko_KR.UTF-8"'>/etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG ko_KR.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8


ENV PATH="/root/.composer/vendor/bin:${PATH}"

RUN apt-get update && apt-get install -my \
    mcrypt \
    libmcrypt-dev \
    git \
    wget \
    unzip \
    gcc \
    make \
    autoconf \
    libc-dev \
    pkg-config \
    libmagickwand-dev \
    build-essential \
    imagemagick \
    mysql-client \
    zlib1g-dev \
    libmemcached-dev \
    libssl-dev \
    libpq-dev \
    libicu-dev \
    subversion \
    g++ \
    libglib2.0-dev \
    python \
    libfcgi0ldbl \
    supervisor \
    cron \
    chrpath && apt-get clean

# Build V8
RUN cd /tmp && \
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
ENV PATH="/tmp/depot_tools:${PATH}"
RUN cd /tmp && \
    fetch v8 && \
    cd v8 && \
    git checkout 5.6.326.12 && \
    gclient sync
RUN cd /tmp/v8 && \
    tools/dev/v8gen.py -vv x64.release -- is_component_build=true
RUN cd /tmp/v8 && \
    ninja -C out.gn/x64.release/

# Install V8
RUN mkdir -p /opt/v8/lib && \
    mkdir -p /opt/v8/include && \
    cd /tmp/v8 && \
    cp out.gn/x64.release/lib*.so out.gn/x64.release/*_blob.bin \
    out.gn/x64.release/icudtl.dat /opt/v8/lib/ && \
    cp -R include/* /opt/v8/include/

# Build V8js
RUN cd /tmp && \
    git clone https://github.com/phpv8/v8js.git && \
    cd v8js && \
    phpize && \
    ./configure --with-v8js=/opt/v8 && \
    make && \
    make test && \
    make install

# Install V8js extensions
RUN echo "extension=v8js.so" > /usr/local/etc/php/conf.d/docker-php-ext-v8js.ini


# Install extensions
RUN docker-php-ext-install mcrypt \
  && docker-php-ext-install gd \
  && docker-php-ext-install opcache \
  && docker-php-ext-install mysqli \
  && docker-php-ext-install pdo \
  && docker-php-ext-install pdo_mysql \
  && docker-php-ext-install soap \
  && docker-php-ext-install sockets \
  && docker-php-ext-install bcmath \
  && docker-php-ext-install zip \
  && docker-php-ext-install pcntl

# Xdebug installation
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug
RUN touch /var/log/xdebug_remote.log && chmod 777 /var/log/xdebug_remote.log

# MongoDB installation
RUN pecl install mongodb \
    && echo "extension=mongodb.so" > /usr/local/etc/php/conf.d/ext-mongodb.ini

# Composer installation
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Add configuration files
COPY conf/php.ini /usr/local/etc/php/php.ini
COPY conf/xdebug.ini /usr/local/etc/php/conf.d/
COPY conf/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY conf/supervisord.conf /etc/supervisord.conf
COPY conf/cronjobs /etc/cron.d/php-app-cronjob

RUN chmod 644 /etc/cron.d/php-app-cronjob

ENV DEBIAN_FRONTEND teletype

CMD ["/usr/bin/supervisord", "-n", "-c",  "/etc/supervisord.conf"]

WORKDIR /var/www/public

EXPOSE 9000
EXPOSE 9001

VOLUME ["/var/www"]

HEALTHCHECK --interval=10s --timeout=10s --retries=10 \
    CMD \
    cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1