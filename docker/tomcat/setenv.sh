#!/bin/sh
#
# Tomcat JVM tuning for Servoy deployments.
# Adjust -Xmx to suit the memory available in your CI runner.

export JAVA_OPTS="\
  -Xms512m \
  -Xmx2g \
  -XX:+UseG1GC \
  -Djava.awt.headless=true \
  -Dfile.encoding=UTF-8 \
"
