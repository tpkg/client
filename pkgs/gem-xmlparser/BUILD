#!/bin/sh

set -e

for i in expat-devel
do
	rpm --quiet -q $i  || sudo yum install $i
done

for i in gem-rake gem-mkrf
do
	tpkg -q $i || tpkg -i $i
done

# Ensure that rake is found
PATH=/home/t/ruby-1.8/bin:/home/t/bin:$PATH
export PATH

gem2tpkg xmlparser --version=0.6.81 --package-version=1 \
  --native-deps=expat

