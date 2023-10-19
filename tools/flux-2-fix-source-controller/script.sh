#!/usr/bin/env sh

FILE_TO_WATCH=/data/gitrepository/flux-giantswarm/giantswarm-config/test
while true
do
  if ! [[ -e $FILE_TO_WATCH ]]
  then
    echo "gone: $FILE_TO_WATCH"
    FILE_TO_WATCH=$(ls -t /data/gitrepository/flux-giantswarm/giantswarm-config/*.tar.gz | grep -v latest | cut -d' ' -f1 | head -2 | tail -1)
    rm /data/gitrepository/flux-giantswarm/giantswarm-config/latest.tar.gz
    ln -s $FILE_TO_WATCH /data/gitrepository/flux-giantswarm/giantswarm-config/latest.tar.gz
  fi
done
