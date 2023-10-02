#!/usr/bin/env bash

set -e

if [ -z "${DOCUMENT_ROOT}" ]
then
    DOCUMENT_ROOT="/www/public"
fi

if [ -z "${PROCESSES_COUNT}" ]
then
    PROCESSES_COUNT=10
fi

if [ -z "${IDLE_TIMEOUT}" ]
then
    IDLE_TIMEOUT=65
fi

if [ -z "${SEND_TIMEOUT}" ]
then
    SEND_TIMEOUT=65
fi

if [ -z "${MEMORY_LIMIT}" ]
then
    MEMORY_LIMIT="256M"
fi

curl_put()
{
    RET=$(/usr/bin/curl -s -w '%{http_code}' -X PUT --data-binary @$1 --unix-socket /var/run/control.unit.sock http://localhost/$2)
    RET_BODY=$(echo $RET | /bin/sed '$ s/...$//')
    RET_STATUS=$(echo $RET | /usr/bin/tail -c 4)
    if [ "$RET_STATUS" -ne "200" ]; then
        echo "$0: Error: HTTP response status code is '$RET_STATUS'"
        echo "$RET_BODY"
        return 1
    else
        echo "$0: OK: HTTP response status code is '$RET_STATUS'"
        echo "$RET_BODY"
    fi
    return 0
}

config_tpl()
{
  sed -i "s|{{DOCUMENT_ROOT}}|${DOCUMENT_ROOT}|" $1
  sed -i "s|{{PROCESSES_COUNT}}|${PROCESSES_COUNT}|" $1
  sed -i "s|{{SEND_TIMEOUT}}|${SEND_TIMEOUT}|" $1
  sed -i "s|{{IDLE_TIMEOUT}}|${IDLE_TIMEOUT}|" $1
  sed -i "s|{{MEMORY_LIMIT}}|${MEMORY_LIMIT}|" $1
}

WAITLOOPS=5
SLEEPSEC=1

if [ "$1" = "unitd" ] || [ "$1" = "unitd-debug" ]; then
    if /usr/bin/find "/var/lib/unit/" -mindepth 1 -print -quit 2>/dev/null | /bin/grep -q .; then
        echo "$0: /var/lib/unit/ is not empty, skipping initial configuration..."
    else
        echo "$0: Launching Unit daemon to perform initial configuration..."
        /usr/sbin/$1 --control unix:/var/run/control.unit.sock

        for i in $(/usr/bin/seq $WAITLOOPS); do
            if [ ! -S /var/run/control.unit.sock ]; then
                echo "$0: Waiting for control socket to be created..."
                /bin/sleep $SLEEPSEC
            else
                break
            fi
        done
        # even when the control socket exists, it does not mean unit has finished initialisation
        # this curl call will get a reply once unit is fully launched
        /usr/bin/curl -s -X GET --unix-socket /var/run/control.unit.sock http://localhost/

        if /usr/bin/find "/docker-entrypoint.d/" -mindepth 1 -print -quit 2>/dev/null | /bin/grep -q .; then
            echo "$0: /docker-entrypoint.d/ is not empty, applying initial configuration..."

            echo "$0: Looking for certificate bundles in /docker-entrypoint.d/..."
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -name "*.pem"); do
                echo "$0: Uploading certificates bundle: $f"
                curl_put $f "certificates/$(basename $f .pem)"
            done

            echo "$0: Looking for JavaScript modules in /docker-entrypoint.d/..."
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -name "*.js"); do
                echo "$0: Uploading JavaScript module: $f"
                curl_put $f "js_modules/$(basename $f .js)"
            done

            echo "$0: Looking for configuration template snippets in /docker-entrypoint.d/..."
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -name "*.json.tpl"); do
                echo "$0: Generating configuration $f";
                config_tpl $f
                echo "$0: Applying configuration $f";
                curl_put $f "config"
            done

            echo "$0: Looking for configuration snippets in /docker-entrypoint.d/..."
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -name "*.json"); do
                echo "$0: Applying configuration $f";
                curl_put $f "config"
            done

            echo "$0: Looking for shell scripts in /docker-entrypoint.d/..."
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -name "*.sh"); do
                echo "$0: Launching $f";
                "$f"
            done

            # warn on filetypes we don't know what to do with
            for f in $(/usr/bin/find /docker-entrypoint.d/ -type f -not -name "*.sh" -not -name "*.json.tpl" -not -name "*.json" -not -name "*.pem" -not -name "*.js"); do
                echo "$0: Ignoring $f";
            done
        else
            echo "$0: /docker-entrypoint.d/ is empty, creating 'welcome' configuration..."
            curl_put /usr/share/unit/welcome/welcome.json "config"
        fi

        echo "$0: Stopping Unit daemon after initial configuration..."
        kill -TERM $(/bin/cat /var/run/unit.pid)

        for i in $(/usr/bin/seq $WAITLOOPS); do
            if [ -S /var/run/control.unit.sock ]; then
                echo "$0: Waiting for control socket to be removed..."
                /bin/sleep $SLEEPSEC
            else
                break
            fi
        done
        if [ -S /var/run/control.unit.sock ]; then
            kill -KILL $(/bin/cat /var/run/unit.pid)
            rm -f /var/run/control.unit.sock
        fi

        echo
        echo "$0: Unit initial configuration complete; ready for start up..."
        echo
    fi
fi

exec "$@"