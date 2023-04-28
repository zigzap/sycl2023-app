#!/bin/bash
source /home/azureuser/.bashrc

set -e 

APP=sycl2023-app
IMG_DEST=/var/www/buildstatus/buildstatus
mkdir -p $IMG_DEST
OUT_IMG=$IMG_DEST/$APP.svg
OUT_TXT=$IMG_DEST/$APP.txt
echo "$(date)" > $OUT_TXT


echo zigup: >> $OUT_TXT
zigup master >> $OUT_TXT 2>&1

cd /home/azureuser/sycl2023-app

echo git pull: >> $OUT_TXT
git pull >> $OUT_TXT 2>&1

echo zig build: >> $OUT_TXT
if  zig build >> $OUT_TXT 2>&1  ; then 
    cp /home/azureuser/sycl2023-app/img/passing.svg $OUT_IMG
else
    cp /home/azureuser/sycl2023-app/img/failing.svg $OUT_IMG
fi
