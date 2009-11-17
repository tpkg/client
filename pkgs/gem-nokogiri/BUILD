#!/bin/sh
for i in libxml2-devel libxslt-devel
do
	rpm --quiet -q $i  || sudo yum -y install $i
done

gem2tpkg nokogiri --version=1.3.3 --package-version=2 \
  --native-deps=libxslt
