# -*- encoding: utf-8 -*-
require File.expand_path('../lib/tpkg/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ['Darren Dao', 'Jason Heiss']
  gem.email         = ['tpkg-users@lists.sourceforge.net']
  gem.description   = %q{tpkg is a tool for packaging and deploying applications}
  gem.summary       = %q{tpkg Application Packaging & Deployment}
  gem.homepage      = 'http://tpkg.github.com/'

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = 'tpkg'
  gem.require_paths = ['lib']
  gem.version       = Tpkg::VERSION

  gem.add_dependency('facter', '~>2.3.0')
  gem.add_dependency('net-ssh')
  gem.add_dependency('kwalify')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('mocha')
  gem.add_development_dependency('open4')
end
