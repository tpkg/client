#!/usr/bin/ruby -w

#
# Test tpkg's ability to upgrade packages
#

require 'test/unit'
require 'tpkgtest'
require 'fileutils'

class TpkgUpgradeTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
  end
  
  def test_upgrade
    pkgfiles = []
    ['a', 'b'].each do |pkgname|
      # Make sure the files in the a packages don't conflict with
      # the b packages
      srcdir = Tempdir.new("srcdir")
      FileUtils.cp(File.join('testpkg', 'tpkg-nofiles.xml'), File.join(srcdir, 'tpkg.xml'))
      FileUtils.mkdir(File.join(srcdir, 'reloc'))
      File.open(File.join(srcdir, 'reloc', pkgname), 'w') do |file|
        file.puts pkgname
      end
      # Make the 'b' packages depend on 'a' so that we ensure that we
      # can upgrade a package on which other packages depend.
      deps = {}
      if pkgname == 'b'
        deps['a'] = {}
      end
      ['1.0', '2.0'].each do |pkgver|
        pkgfiles << make_package(:change => {'name' => pkgname, 'version' => pkgver}, :source_directory => srcdir, :dependencies => deps, :remove => ['operatingsystem', 'architecture', 'posix_acl', 'windows_acl'])
      end
      FileUtils.rm_rf(srcdir)
    end
    
    testroot = Tempdir.new("testroot")
    FileUtils.mkdir_p(File.join(testroot, 'home', 'tpkg'))
    tpkg = Tpkg.new(:file_system_root => testroot, :base => File.join('home', 'tpkg'), :sources => pkgfiles)
    
    tpkg.install(['a=1.0', 'b=1.0'], PASSPHRASE)
    
    assert_nothing_raised { tpkg.upgrade(['a']) }
    # Should have two packages installed:  a-2.0 and b-1.0
    metadata = tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m.elements['/tpkg/name'].text == 'a'
        apkg = m
      elsif m.elements['/tpkg/name'].text == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg.elements['/tpkg/version'].text)
    assert_not_nil(bpkg)
    assert_equal('1.0', bpkg.elements['/tpkg/version'].text)

    assert_nothing_raised { tpkg.upgrade }
    # Should have two packages installed:  a-2.0 and b-2.0
    metadata = tpkg.metadata_for_installed_packages
    assert_equal(2, metadata.length)
    apkg = nil
    bpkg = nil
    metadata.each do |m|
      if m.elements['/tpkg/name'].text == 'a'
        apkg = m
      elsif m.elements['/tpkg/name'].text == 'b'
        bpkg = m
      end
    end
    assert_not_nil(apkg)
    assert_equal('2.0', apkg.elements['/tpkg/version'].text)
    assert_not_nil(bpkg)
    assert_equal('2.0', bpkg.elements['/tpkg/version'].text)
    
    pkgfiles.each { |pkgfile| FileUtils.rm_f(pkgfile) }
    FileUtils.rm_rf(testroot)
  end
end

