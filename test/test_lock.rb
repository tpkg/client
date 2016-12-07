

#
# Test tpkg's ability to lock/unlock the package repository
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgLockTests < Test::Unit::TestCase
  include TpkgTests

  def setup
    Tpkg::set_prompt(false)

    # Make up our regular test package
    @pkgfile = make_package(:remove => ['operatingsystem', 'architecture'])

    # Make a test repository
    @testbase = Dir.mktmpdir('testbase')
  end

  def test_lock
    # Lock the repo
    tpkg = Tpkg.new(:base => @testbase)
    assert_nothing_raised('lock') { tpkg.lock }

    # Verify that an operation requiring a lock works with this instance
    assert_nothing_raised('install') { tpkg.install([@pkgfile], PASSPHRASE) }

    # Make a seperate instance of Tpkg using the same repo
    tpkg2 = Tpkg.new(:base => @testbase)
    # Verify that attempting a lock with this instance fails
    assert_raise(RuntimeError, 'lock in other instance') { tpkg2.lock }
    # Verify that an operation requiring a lock fails with this instance
    assert_raise(RuntimeError, 'install in other instance') { tpkg2.install([@pkgfile], PASSPHRASE) }
    # Verify that attempting to unlock this instance fails
    # Decided to have it just warn rather than throw an exception
    #assert_raise(RuntimeError, 'unlock in other instance') { tpkg2.unlock }

    # Re-verify that things work with the original instance
    assert_nothing_raised('remove') { tpkg.remove(['testpkg']) }

    # Unlock the repo
    assert_nothing_raised('unlock') { tpkg.unlock }
  end

  def test_old_lock
    # Create a lock that is more than 2 hours old
    FileUtils.mkdir_p(File.join(@testbase, 'var', 'tpkg', 'lock'))
    File.open(File.join(@testbase, 'var', 'tpkg', 'lock', 'pid'), 'w') { |file| file.puts($$) }
    threehoursago = Time.at(Time.now - 60*60*3)
    File.utime(threehoursago, threehoursago, File.join(@testbase, 'var', 'tpkg', 'lock'))

    tpkg = Tpkg.new(:base => @testbase)

    # Verify that tpkg will lock, removing the stale lock file
    assert_nothing_raised('lock') { tpkg.lock }
    assert_nothing_raised('unlock') { tpkg.unlock }
  end

  def test_lock_force
    # Create a lock
    FileUtils.mkdir_p(File.join(@testbase, 'var', 'tpkg', 'lock'))
    File.open(File.join(@testbase, 'var', 'tpkg', 'lock', 'pid'), 'w') { |file| file.puts($$) }

    # Verify that locking fails without the :lockforce option
    tpkg = Tpkg.new(:base => @testbase)
    assert_raise(RuntimeError) { tpkg.lock }

    # Set the :lockforce option
    tpkg = Tpkg.new(:base => @testbase, :lockforce => true)

    # Verify that tpkg will lock, removing the lock file
    assert_nothing_raised('lock') { tpkg.lock }
    assert_nothing_raised('unlock') { tpkg.unlock }
  end

  def teardown
    FileUtils.rm_f(@pkgfile)
    FileUtils.rm_rf(@testbase)
  end
end
