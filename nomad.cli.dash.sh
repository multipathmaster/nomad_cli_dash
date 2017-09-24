#!/bin/bash
CONSUL_IP_ADD=$1
DNS_IP_PRT=$2
NOMAD_IP_ADD=$3
NPRT=$4
CYCLES=$5
NAPI="/v1/allocation/"
NAPIGC="/v1/system/gc"

if [[ $# -lt 5 ]]; then
  echo "Not enough arguments given."
  echo "Example:  ./nomad.cli.dash.sh CONSUL_IP_ADD DNS_IP_PRT NOMAD_IP_ADD API_PORT CYCLE_COUNT"
  echo "Practical:  ./nomad.cli.dash.sh 10.10.10.42 8600 10.10.10.42 4646 2"
  exit 1
fi

#BUILD BINARY FOR EVERY NEW RUN
go build http.get.go

while : ; do

debugger(){
set -x
}

tags_names(){
for x in `./http.get http://${NOMAD_IP_ADD}:${NPRT}/v1/allocations | jq -r '.[] | {ID}' | awk '{ print $2 }' | sed '/^$/d' | sed s/\"//g`; do
  echo $x
  ./http.get http://${NOMAD_IP_ADD}:${NPRT}${NAPI}${x} | jq -r '.ID, .TaskResources, .Job'
done | grep -A1 Tag | awk -F "\"" '{ print $2 }' | sed '/^$/d' | grep -v Tags > Tags.$$

for x in `./http.get http://${NOMAD_IP_ADD}:${NPRT}/v1/allocations | jq -r '.[] | {ID}' | awk '{ print $2 }' | sed '/^$/d' | sed s/\"//g`; do
  echo $x
  ./http.get http://${NOMAD_IP_ADD}:${NPRT}${NAPI}${x} | jq -r '.ID, .TaskResources, .Job'
done | grep -A2 Services | awk -F"\"" '{ print $4 }' | sed '/^$/d' > Names.$$
}

do_it(){
refresh_cache
tags_names

#GET THE DIG FILE
for x in `paste -d'.' Tags.$$ Names.$$`; do
  echo "${x}.service.consul"
done > DigFile.$$

#CREATE MAP FILE WITH PORT AT TOP AND IP AT BOTTOM
for x in `cat DigFile.$$`; do
  dig @${CONSUL_IP_ADD} -p ${DNS_IP_PRT} ${x} SRV | egrep '(consul.)' | grep -v ";" | grep -o '[0-9]\+.[0-9]\+.[0-9]\+.[0-9]\+' | sed s/[0-9]\ [0-9]\ //g > ${x}.map
done

#CREATE IP FILE FOR INDIVIDUAL SERVICE THAT IS DETECTED
for x in `ls *.map`; do
  cat ${x} | grep "\." > ${x}.ip
done

#CREATE PORT FILE FOR IND SERVICE
for x in `ls *.map`; do
  cat ${x} | grep -v "\." > ${x}.port
done

#CREATE SERVICE FILE WITH COMBINATION
for x in `ls *.map`; do
  paste -d':' ${x}.ip ${x}.port > mappings/${x}.SERVICE
done

#DETECTING PENDING OR STOPPING JOBS AND OMMITING THEM WHICH SHOULD CAUSE A GC TO HAPPEN
for x in `grep "^\:" mappings/*.SERVICE | awk -F "\:" '{ print $1 }'`; do
  rm -f ${x}
done

#CREATING THE CACHE TO PULL FROM
cp -p mappings/*.SERVICE mappings/cache/.
if [[ $? -ne 0 ]]; then
  echo "Could not copy files into cache for some reason."
  cleanup
  exit 1
fi
}

#SHOW THE MAPPINGS
show_me(){
clear
for x in `ls mappings/cache/.`; do
  echo ${x}; cat mappings/cache/${x}
  printf "\n"
done
date
}

#REFRESH CACHE/ALERT TRIGGER
refresh_cache(){
BEFORE=`ls mappings/cache/. | wc -l`
find mappings/cache -type f -mtime +`expr ${CYCLES} + 4`s -delete
AFTER=`ls mappings/cache/. | wc -l`
if [[ ${BEFORE} -ne ${AFTER} ]]; then
  echo "Showing what changed."
  diff --brief -Nr mappings/cache/. mappings/. | awk '{ print $NF }' | grep -v cache
  echo "Change detected, forcing GC."
  curl -s -X PUT http://${NOMAD_IP_ADD}:${NPRT}${NAPIGC}
else
  echo "Nothing changed, skipping GC."
fi
}

#CLEANUP THE MESS
cleanup(){
rm -f *.port
rm -f *.ip
rm -f *.map
rm -f Tags.$$
rm -f Names.$$
rm -f DigFile.$$
rm -f mappings/*.SERVICE
}

main(){
#debugger
do_it
show_me
cleanup
}

main

sleep ${CYCLES}
done
