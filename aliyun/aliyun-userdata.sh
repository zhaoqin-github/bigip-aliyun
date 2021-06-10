#!/bin/bash

cat userdata

echo "    content: "$(gzip -c aliyun-setup.sh | base64 -w0)
