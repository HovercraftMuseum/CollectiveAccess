# syntax=docker/dockerfile:1
#
# CollectiveAccess Providence container image
#
# Two things are pinned here and they update through different channels:
#
#   1. The runtime (PHP base image, PHP extensions, media tools).
#      Renovate keeps the base image digest current and CI rebuilds weekly,
#      so security patches arrive automatically under the same CA version tag.
#
#   2. The application (CA_VERSION + CA_SHA256).
#      Only ever changed by a person, after reading the release notes.
#      See docs/upgrading.md.
#
# Both FROM lines must name the same base image; Renovate updates them together.
#
# PHP 8.4: the release's bundled vendor/ directory requires PHP >= 8.4.

# CollectiveAccess Providence release to package. Single source of truth.
# When changing CA_VERSION you MUST also update CA_SHA256 (see docs/upgrading.md).
ARG CA_VERSION=2.0.12
ARG CA_SHA256=11c240907225ed08b3439b70f41b08596c87dde17245bb92d68509a2db31d536

# ---------------------------------------------------------------------------
# Stage 1: fetch and verify the official release package
# ---------------------------------------------------------------------------
FROM php:8.4-apache-trixie AS source

ARG CA_VERSION
ARG CA_SHA256

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSL -o providence.zip \
      "https://github.com/collectiveaccess/providence/releases/download/${CA_VERSION}/providence-${CA_VERSION}.zip" \
 && echo "${CA_SHA256}  providence.zip" | sha256sum -c - \
 && mkdir providence \
 && unzip -q providence.zip -d providence \
 && rm providence.zip \
 # Remove things a production install does not need
 && rm -rf providence/tests providence/Vagrantfile* providence/.git* \
 # Sanity check: the version we asked for is the version we got
 && grep -q "__CollectiveAccess_Version__', '${CA_VERSION}'" providence/app/version.php

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM php:8.4-apache-trixie AS runtime

ARG CA_VERSION
# LibreOffice adds ~600 MB. Only needed for previews/indexing of Word, Excel
# and PowerPoint files. Build with --build-arg INSTALL_LIBREOFFICE=true to add it.
ARG INSTALL_LIBREOFFICE=false

LABEL org.opencontainers.image.title="CollectiveAccess Providence" \
      org.opencontainers.image.description="CollectiveAccess Providence cataloguing application with media tools" \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.collectiveaccess.version="${CA_VERSION}"

# Helper that installs PHP extensions and their system libraries in one step.
COPY --from=ghcr.io/mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/

# PHP extensions.
# Required by CA:     gd curl mysqli zip xml mbstring intl bcmath gmp opcache
#                     (curl, xml, mbstring, posix ship with the base image)
# Recommended by CA:  pcntl/posix (background processes), redis (cache)
# Image processing:   imagick. CA advises never installing both imagick and
#                     gmagick extensions together, so we only install imagick.
RUN install-php-extensions \
      bcmath \
      exif \
      gd \
      gmp \
      imagick \
      intl \
      mysqli \
      opcache \
      pcntl \
      pdo_mysql \
      redis \
      zip

# Command-line tools CA uses for media processing and metadata extraction.
#   ffmpeg          audio/video transcoding (required for AV)
#   ghostscript     PDF previews
#   graphicsmagick  CA's preferred image processor (CLI)
#   imagemagick     fallback and HEIC support
#   poppler-utils   pdftotext for PDF full-text indexing
#   mediainfo       technical metadata for audio/video
#   exiftool        embedded image metadata
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
      ffmpeg \
      ghostscript \
      graphicsmagick \
      imagemagick \
      libimage-exiftool-perl \
      mediainfo \
      poppler-utils \
 && if [ "${INSTALL_LIBREOFFICE}" = "true" ]; then \
      apt-get install -y --no-install-recommends \
        libreoffice-core libreoffice-writer libreoffice-calc libreoffice-impress ; \
    fi \
 && rm -rf /var/lib/apt/lists/*

# PHP and Apache configuration
COPY docker/php/collectiveaccess.ini "$PHP_INI_DIR/conf.d/zz-collectiveaccess.ini"
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/apache/collectiveaccess.conf /etc/apache2/conf-available/collectiveaccess.conf
RUN a2enmod rewrite headers expires remoteip \
 && a2enconf collectiveaccess

# Application code (immutable inside the image)
COPY --from=source /src/providence/ /var/www/html/

# Default setup.php: reads every setting from environment variables and
# contains no secrets. To use your own instead, mount it over this file
# (see compose.yaml). A mounted file is never touched by image updates.
COPY docker/setup.php /var/www/html/setup.php

# Static health check target (allowed by CA's .htaccess because it is .txt)
RUN echo "ok" > /var/www/html/healthz.txt

# Writable directories. Compose mounts volumes on tmp and log; the
# entrypoint creates the folders inside tmp. The media uploader's staging
# folder moves from the web root into tmp.
RUN mkdir -p /var/lib/collectiveaccess/tmp /var/lib/collectiveaccess/log \
             /var/www/html/media/collectiveaccess \
 && grep -q '^media_uploader_root_directory = ' /var/www/html/app/conf/app.conf \
 && sed -i 's|^media_uploader_root_directory = .*|media_uploader_root_directory = /var/lib/collectiveaccess/tmp/media-uploads|' \
        /var/www/html/app/conf/app.conf \
 && rm -rf /var/www/html/uploads \
 && chown -R www-data:www-data /var/lib/collectiveaccess /var/www/html/media \
        /var/www/html/app/fonts \
        /var/www/html/vendor/ezyang/htmlpurifier/library/HTMLPurifier/DefinitionCache

COPY docker/entrypoint.sh /usr/local/bin/ca-entrypoint
COPY docker/cautils /usr/local/bin/cautils
RUN chmod 0755 /usr/local/bin/ca-entrypoint /usr/local/bin/cautils

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost/healthz.txt >/dev/null || exit 1

WORKDIR /var/www/html
ENTRYPOINT ["ca-entrypoint"]
CMD ["apache2-foreground"]
