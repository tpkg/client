#!/bin/sh

tpkg -q gem-ruby-oci8 || tpkg -i gem-ruby-oci8
gem2tpkg activerecord-oracle-adapter --install-options "--source http://gems.rubyonrails.org" --extra-deps=gem-ruby-oci8

