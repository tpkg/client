#!/bin/sh

for i in libxml2-devel libxslt-devel
do
	rpm --quiet -q $i  || sudo yum install $i
done

gem2tpkg nokogiri --version=1.4.2 --package-version=1 \
  --native-deps=libxml2,,,libxslt,,,

