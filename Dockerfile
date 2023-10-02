ARG PHP_VERSION=8.2.11
ARG UNIT_VERSION=1.31.0-1
ARG COMPOSER_VERSION=2.5.8

FROM php:${PHP_VERSION}-cli AS builder

RUN set -ex \
    && savedAptMark="$(apt-mark showmanual)" \
    && apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y ca-certificates mercurial build-essential libssl-dev libpcre2-dev curl pkg-config \
    && mkdir -p /usr/lib/unit/modules /usr/lib/unit/debug-modules \
    && hg clone -u "${UNIT_VERSION}" https://hg.nginx.org/unit \
    && cd unit \
    && NCPU="$(getconf _NPROCESSORS_ONLN)" \
    && DEB_HOST_MULTIARCH="$(dpkg-architecture -q DEB_HOST_MULTIARCH)" \
    && CC_OPT="$(DEB_BUILD_MAINT_OPTIONS="hardening=+all,-pie" DEB_CFLAGS_MAINT_APPEND="-Wp,-D_FORTIFY_SOURCE=2 -fPIC" dpkg-buildflags --get CFLAGS)" \
    && LD_OPT="$(DEB_BUILD_MAINT_OPTIONS="hardening=+all,-pie" DEB_LDFLAGS_MAINT_APPEND="-Wl,--as-needed -pie" dpkg-buildflags --get LDFLAGS)" \
    && CONFIGURE_ARGS_MODULES="--prefix=/usr \
    --statedir=/var/lib/unit \
    --control=unix:/var/run/control.unit.sock \
    --pid=/var/run/unit.pid \
    --log=/var/log/unit.log \
    --tmpdir=/var/tmp \
    --user=unit \
    --group=unit \
    --openssl \
    --libdir=/usr/lib/$DEB_HOST_MULTIARCH" \
    && CONFIGURE_ARGS="$CONFIGURE_ARGS_MODULES \
    --njs" \
    && make -j $NCPU -C pkg/contrib .njs \
    && export PKG_CONFIG_PATH=$(pwd)/pkg/contrib/njs/build \
    && ./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --ld-opt="$LD_OPT" --modulesdir=/usr/lib/unit/debug-modules --debug \
    && make -j $NCPU unitd \
    && install -pm755 build/sbin/unitd /usr/sbin/unitd-debug \
    && make clean \
    && ./configure $CONFIGURE_ARGS --cc-opt="$CC_OPT" --ld-opt="$LD_OPT" --modulesdir=/usr/lib/unit/modules \
    && make -j $NCPU unitd \
    && install -pm755 build/sbin/unitd /usr/sbin/unitd \
    && make clean \
    && ./configure $CONFIGURE_ARGS_MODULES --cc-opt="$CC_OPT" --modulesdir=/usr/lib/unit/debug-modules --debug \
    && ./configure php \
    && make -j $NCPU php-install \
    && make clean \
    && ./configure $CONFIGURE_ARGS_MODULES --cc-opt="$CC_OPT" --modulesdir=/usr/lib/unit/modules \
    && ./configure php \
    && make -j $NCPU php-install \
    && cd \
    && rm -rf unit \
    && for f in /usr/sbin/unitd /usr/lib/unit/modules/*.unit.so; do \
    ldd $f | awk '/=>/{print $(NF-1)}' | while read n; do dpkg-query -S $n; done | sed 's/^\([^:]\+\):.*$/\1/' | sort | uniq >> /requirements.apt; \
    done \
    && apt-mark showmanual | xargs apt-mark auto > /dev/null \
    && { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; } \
    && ldconfig \
    && mkdir -p /var/lib/unit/ \
    && mkdir /docker-entrypoint.d/ \
    && groupadd --gid 999 unit \
    && useradd \
    --uid 999 \
    --gid unit \
    --no-create-home \
    --home /nonexistent \
    --comment "unit user" \
    --shell /bin/false \
    unit \
    && apt-get update \
    && apt-get --no-install-recommends --no-install-suggests -y install curl $(cat /requirements.apt) \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /dev/stdout /var/log/unit.log

FROM composer:${COMPOSER_VERSION} AS composer

FROM php:${PHP_VERSION}-cli

COPY docker-entrypoint.sh /usr/local/bin/
COPY --from=builder /usr/sbin/unitd /usr/sbin/unitd
COPY --from=builder /usr/sbin/unitd-debug /usr/sbin/unitd-debug
COPY --from=builder /usr/lib/unit/ /usr/lib/unit/
COPY --from=builder /requirements.apt /requirements.apt
RUN ldconfig
RUN set -x \
    && mkdir -p /var/lib/unit/ \
    && mkdir /docker-entrypoint.d/ \
    && addgroup unit \
    && adduser \
    --uid 1000 \
    --disabled-login \
    --ingroup unit \
    --no-create-home \
    --home /unit \
    --gecos "unit user" \
    --shell /bin/false \
    unit \
    && apt update \
    && apt --no-install-recommends --no-install-suggests -y install curl $(cat /requirements.apt) \
    && rm -f /requirements.apt \
    && ln -sf /dev/stdout /var/log/unit.log

RUN apt-get update
RUN apt-get install -y zlib1g-dev libfreetype6-dev libjpeg62-turbo-dev libpng-dev libicu-dev libpq-dev libxml++2.6-dev libxslt1-dev libzip-dev wget ca-certificates ssh git iputils-ping iproute2 libgpgme-dev

ARG XDEBUG_VERSION

RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install gd bcmath intl opcache pdo_pgsql pgsql soap sockets xsl zip
RUN docker-php-ext-configure pcntl --enable-pcntl
RUN docker-php-ext-install pcntl
RUN pecl install redis igbinary gnupg
RUN docker-php-ext-enable redis igbinary gnupg
RUN pecl install xdebug-3.2.0

ENV PHP_DATE_TIMEZONE UTC
ENV PHP_OPCACHE_VALIDATE_TIMESTAMPS 0
ENV PHP_DISPLAY_STARTUP_ERRORS off
ENV PHP_DISPLAY_ERRORS off
ENV PHP_DDTRACE_DISABLE on

COPY ./php.ini /usr/local/etc/php/conf.d/90-base-image.ini
COPY ./config.json /docker-entrypoint.d/config.json.tpl

ARG DATADOG_VERSION
ARG TARGETARCH

COPY ./install-ddtrace.sh /install-ddtrace.sh
RUN /install-ddtrace.sh
RUN rm /install-ddtrace.sh

COPY ./xdebug /usr/local/bin/xdebug

COPY --from=composer /usr/bin/composer /usr/bin/composer

RUN mkdir /unit
RUN chown unit:unit /unit
RUN chown unit:unit -R /var/lib/unit
RUN chown unit:unit -R /docker-entrypoint.d
RUN chown unit:unit -R /usr/local/etc/php/conf.d
RUN chmod 0777 /run

# unit
USER 1000

RUN mkdir -m 0700 ~/.ssh
RUN touch ~/.ssh/known_hosts
RUN chmod 0644 ~/.ssh/known_hosts

RUN ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
RUN ssh-keyscan -t rsa gitlab.com >> ~/.ssh/known_hosts
RUN ssh-keyscan -t rsa bitbucket.org >> ~/.ssh/known_hosts

ENV COMPOSER_MEMORY_LIMIT=-1

USER root

RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/*

RUN mkdir -p /www/public
RUN chown unit:unit /www/public

# unit
USER 1000

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/control.unit.sock"]

ONBUILD USER root
