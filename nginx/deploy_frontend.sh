#!/usr/bin/env bash
ssh zigzap "cd sycl2023-app && git pull && ./nginx/deploy.sh"
