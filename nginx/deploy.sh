#!/bin/bash

sudo rm -fr /var/www/sycl2023/sycl2023
sudo mkdir -p /var/www/sycl2023/sycl2023
sudo cp -pvr frontend/* /var/www/sycl2023/sycl2023
sudo chown -R azureuser:www-data /var/www/sycl2023
sudo chmod -R 0755 /var/www/sycl2023
