#!/bin/bash

set -ex

echo "Current $TARGETARCH"

wget -q "https://github.com/DataDog/dd-trace-php/releases/download/${DATADOG_VERSION}/datadog-php-tracer_${DATADOG_VERSION}_${TARGETARCH}.deb"
dpkg -i datadog-php-tracer_${DATADOG_VERSION}_${TARGETARCH}.deb
rm datadog-php-tracer_${DATADOG_VERSION}_${TARGETARCH}.deb

echo "datadog.curl_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.elasticsearch_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.guzzle_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.symfony_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.trace.analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.trace.curl_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.trace.elasticsearch_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.trace.guzzle_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "datadog.trace.symfony_analytics_enabled=On" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
echo "ddtrace.disable=\${PHP_DDTRACE_DISABLE}" >> /usr/local/etc/php/conf.d/99-ddtrace-custom.ini
