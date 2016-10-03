FROM onnimonni/alpine-base
MAINTAINER Onni Hakala <onni.hakala@geniem.com>

# Additional modules for nginx
ARG NGX_MOD_CACHE_PURGE_VERSION="2.3"

# Build Arguments for openresty/nginx
ARG RESTY_VERSION="1.11.2.1"
ARG RESTY_OPENSSL_VERSION="1.0.2h"
ARG RESTY_PCRE_VERSION="8.39"
ARG RESTY_CONFIG_OPTIONS="\
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_geoip_module=dynamic \
    --with-http_image_filter_module=dynamic \
    --with-http_xslt_module=dynamic \

    --with-file-aio \
    --with-ipv6 \
    --with-md5-asm \
    --with-pcre-jit \
    --with-sha1-asm \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \

    --without-http_autoindex_module \
    --without-http_browser_module \
    --without-http_userid_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --without-http_split_clients_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_referer_module \

     --user=nginx \
     --group=nginx \

    --sbin-path=/usr/sbin \
    --modules-path=/usr/lib/nginx \

    --prefix=/etc/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --http-log-path=/var/log/nginx/access.log \
    --error-log-path=/var/log/nginx/error.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx/nginx.lock \

    --http-fastcgi-temp-path=/tmp/nginx/fastcgi \
    --http-proxy-temp-path=/tmp/nginx/proxy \
    --http-client-body-temp-path=/tmp/nginx/client_body \
    "

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-openssl=/tmp/openssl-${RESTY_OPENSSL_VERSION} --with-pcre=/tmp/pcre-${RESTY_PCRE_VERSION}"

# 1) Install apk dependencies
# 2) Download and untar OpenSSL, PCRE, and OpenResty
# 3) Build OpenResty
# 4) Cleanup

RUN \
    apk add --no-cache --virtual .build-deps \
        build-base \
        openssl \
        gd-dev \
        geoip-dev \
        libxslt-dev \
        linux-headers \
        make \
        perl-dev \
        readline-dev \
        zlib-dev \
    && apk add --no-cache \
        gd \
        geoip \
        libgcc \
        libxslt \
        zlib \
    && cd /tmp \

    # Download and unpack all dependencies
    && wget -O- https://www.openssl.org/source/openssl-${RESTY_OPENSSL_VERSION}.tar.gz | tar -zx \
    && wget -O- https://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-${RESTY_PCRE_VERSION}.tar.gz | tar -zx \
    && wget -O- https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz | tar -zx \

    # Add and validate nginx cache purge module
    && wget https://github.com/FRiCKLE/ngx_cache_purge/archive/${NGX_MOD_CACHE_PURGE_VERSION}.tar.gz -O ngx_cache_purge-${NGX_MOD_CACHE_PURGE_VERSION}.tar.gz \
    && validate_sha256sum ngx_cache_purge-${NGX_MOD_CACHE_PURGE_VERSION}.tar.gz cb7d5f22919c613f1f03341a1aeb960965269302e9eb23425ccaabd2f5dcbbec \
    && tar -xzf ngx_cache_purge-${NGX_MOD_CACHE_PURGE_VERSION}.tar.gz \

    # Use all cores available in the builds with -j${NPROC} flag
    && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
    && echo "using up to $NPROC threads" \

    # Configure and build nginx with openresty packages
    && cd /tmp/openresty-${RESTY_VERSION} \
    && ./configure -j${NPROC} ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} \
    && make -j${NPROC} \
    && make -j${NPROC} install \

    # Remove unneccessary nginx files
    && rm /etc/nginx/*.default \

    # Cleanup
    && rm -rf /tmp/* \
    && apk del .build-deps

RUN \
    # Temp directory
    mkdir /tmp/nginx/ \

    # Symlink modules path to config path for easier usage
    && ln -sf /usr/lib/nginx /etc/nginx/modules \

    # Create nginx group
    && addgroup -S nginx -g 8889 \
    && adduser -S -G nginx -u 8888 nginx \

    # Symlink nginx logs to system output
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

ENV \
    # Custom port for nginx
    PORT=8080 \

    # Custom web root for nginx
    WEB_ROOT="/var/www/project/web" \

    # Include nginx http and server configs from custom folder
    NGINX_INCLUDE_DIR="/var/www/project/nginx" \

    # Set reasonable default upload size
    NGINX_MAX_BODY_SIZE="5M" \

    # Set reasonable timeout for nginx and fastcgi
    NGINX_TIMEOUT="30"

ADD rootfs /
