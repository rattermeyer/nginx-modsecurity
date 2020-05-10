ARG VERSION=1.18.0-alpine

FROM alpine:3.9 as build
RUN apk add --no-cache \
		pcre-dev \
		libxml2-dev \
		git \
		libtool \
		automake \
		autoconf \
		g++ \
		flex \
		bison \
		yajl-dev \
		zlib-dev \
		make \
		libxslt-dev \
		linux-headers
RUN apk add --no-cache curl-dev geoip-dev libmaxminddb-dev lmdb-dev lmdb lua-dev doxygen

FROM alpine:3.9 as libmodsecurity-src
ARG LIB_VERSION=v3.0.4
RUN apk add --no-cache git curl
RUN mkdir -p /usr/src && cd /usr/src \
	&& git clone https://github.com/SpiderLabs/ModSecurity \
	&& cd ModSecurity \
	&& git checkout ${LIB_VERSION} \
	&& git submodule init \
	&& git submodule update

FROM build as libmodsecurity
COPY --from=libmodsecurity-src /usr/src/ModSecurity /usr/src/ModSecurity
WORKDIR /usr/src/ModSecurity
RUN sh build.sh && ./configure && make && make install
RUN cp /usr/src/ModSecurity/modsecurity.conf-recommended /usr/local/modsecurity/modsecurity.conf
RUN cp /usr/src/ModSecurity/unicode.mapping /usr/local/modsecurity/unicode.mapping

FROM nginx:${VERSION} as builder
ENV MORE_HEADERS_VERSION=0.33
ENV MORE_HEADERS_GITREPO=openresty/headers-more-nginx-module
ENV MODSECURITY_NGINX=v1.0.1

COPY --from=libmodsecurity /usr/local/modsecurity /usr/local/modsecurity

# Download sources
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
    wget "https://github.com/${MORE_HEADERS_GITREPO}/archive/v${MORE_HEADERS_VERSION}.tar.gz" -O extra_module.tar.gz && \
    wget "https://github.com/SpiderLabs/ModSecurity-nginx/releases/download/v1.0.1/modsecurity-nginx-${MODSECURITY_NGINX}.tar.gz" -O modsecurity-nginx.tar.gz

# For latest build deps, see https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN  apk add --no-cache --virtual .build-deps \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    libedit-dev \
    mercurial \
    bash \
    alpine-sdk \
    findutils

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN rm -rf /usr/src/nginx /usr/src/extra_module && mkdir -p /usr/src/nginx /usr/src/extra_module /usr/src/modsecurity-nginx && \
    tar -zxC /usr/src/nginx -f nginx.tar.gz && \
    tar -xzC /usr/src/extra_module -f extra_module.tar.gz && \
    tar -zxC /usr/src/modsecurity-nginx --strip-components=1 -f modsecurity-nginx.tar.gz

WORKDIR /usr/src/nginx/nginx-${NGINX_VERSION}

# Reuse same cli arguments as the nginx:alpine image used to build
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
    sh -c "./configure --with-compat $CONFARGS --add-dynamic-module=/usr/src/extra_module/*" && make modules
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
    sh -c "./configure --with-compat $CONFARGS --add-dynamic-module=/usr/src/modsecurity-nginx" && make modules


# Production container starts here
FROM nginx:${VERSION}
ARG NGINX_VERSION=1.18.0

COPY --from=builder /usr/src/nginx/nginx-${NGINX_VERSION}/objs/*_module.so /etc/nginx/modules/

# Validate the config
RUN nginx -t
