#!/bin/bash

source /common.sh

if [[ ! -d /host/usr/bin ]]; then
  echo "ERROR: there is no mount /host/usr/bin from Host's /usr/bin. Utility contrail-tools could not be created."
  exit 1
fi

if [[ -z "$CONTRAIL_STATUS_IMAGE" ]]; then
  echo 'ERROR: variable $CONTRAIL_STATUS_IMAGE is not defined. Utility contrail-tools could not be created.'
  exit 1
fi

vol_opts=''
# ssl folder is always to mounted: in case of IPA init container
# should not generate cert and is_ssl_enabled is false for this container,
# certs&keys are generated by IPA
vol_opts+=' -v /etc/hosts:/etc/hosts:ro'
vol_opts+=' -v /etc/localtime:/etc/localtime:ro'
vol_opts+=' -v /var/run:/var/run'
vol_opts+=' -v /dev:/dev'
vol_opts+=' -v /var/lib/containers:/var/lib/containers'
if [[ -e /etc/contrail ]] ; then
  vol_opts+=' -v /etc/contrail:/etc/contrail:ro'
fi

image=$(echo ${CONTRAIL_STATUS_IMAGE} | sed 's/contrail-status:/contrail-tools:/')
tmp_suffix="--rm --pid host --net host --privileged ${image}"
tmp_file=/host/usr/bin/contrail-tools.tmp.${RANDOM}
cat > $tmp_file << EOM
#!/bin/bash

vol_opts="$vol_opts"
if [[ -n "${SERVER_CA_CERTFILE}" ]] && [[ -e ${SERVER_CA_CERTFILE} ]] ; then
  # In case of FreeIPA CA file is palced in /etc/ipa/ca.crt
  # and should be mounted additionally
  if [[ ! "${SERVER_CA_CERTFILE}" =~ "/etc/contrail/ssl" ]] ; then
    vol_opts+=" -v ${SERVER_CA_CERTFILE}:${SERVER_CA_CERTFILE}:ro"
  fi
fi

interactive_key='-i'
[ -t 0 ] && interactive_key+='t'

cont_name="contrail-tools_\$(head /dev/urandom | tr -dc a-z0-9 | head -c 13)"

name_opts="--name=\$cont_name"

if [[ -n "\$@" ]]; then
  entrypoint=\$(mktemp)
  echo '#!/bin/bash -e' > \$entrypoint
  echo "\$@" >> \$entrypoint
  chmod a+x \$entrypoint
  entrypoint_arg="-v \$entrypoint:\$entrypoint --entrypoint \$entrypoint"
fi

u=\$(which docker 2>/dev/null)
if pidof dockerd >/dev/null 2>&1 || pidof dockerd-current >/dev/null 2>&1 ; then
    trap "\$u rm -f \$cont_name" SIGHUP
    \$u run \$name_opts \$vol_opts \$entrypoint_arg \$interactive_key $tmp_suffix
    rm -f \$entrypoint
    exit \$?
fi
u=\$(which podman 2>/dev/null)
if ((\$? == 0)); then
    trap "\$u rm -f \$cont_name" SIGHUP
    r="\$u run \$name_opts \$vol_opts \$entrypoint_arg "
    r+=' --volume=/run/runc:/run/runc'
    r+=' --volume=/sys/fs:/sys/fs'
    r+=' --security-opt seccomp=unconfined'
    \$r \$interactive_key $tmp_suffix
    rm -f \$entrypoint
    exit \$?
fi
EOM

echo "INFO: generated contrail-tools"
cat $tmp_file

chmod 755 $tmp_file
mv -f $tmp_file /host/usr/bin/contrail-tools
