

#
# Test tpkg's encrypt/decrypt methods
#
# The methods are supposed to be compatible with openssl's 'enc' utility,
# so we test them by encrypting some plaintext with openssl and then using
# the method to decrypt it or vice-versa.
#

require File.expand_path('tpkgtest', File.dirname(__FILE__))

class TpkgEncryptTests < Test::Unit::TestCase
  include TpkgTests
  
  def setup
    Tpkg::set_prompt(false)
  end
  
  def test_encrypt
    plaintext = 'This is the plaintext'
    cipher = 'aes-256-cbc'
    
    tmpfile = Tempfile.new('tpkgtest')
    tmpfile.write(plaintext)
    tmpfile.close
    File.chmod(0604, tmpfile.path)
    
    # Test encrypt
    Tpkg::encrypt('tpkgtest', tmpfile.path, PASSPHRASE, cipher)
    decrypted = `openssl enc -d -#{cipher} -pass pass:#{PASSPHRASE} -in #{tmpfile.path}`
    assert_equal(plaintext, decrypted)
    assert_equal(0604, File.stat(tmpfile.path).mode & 07777)
    
    # Test using a callback to supply the passphrase
    File.open(tmpfile.path, 'w') do |file|
      file.write(plaintext)
    end
    callback = lambda { |pkgname| PASSPHRASE }
    Tpkg::encrypt('tpkgtest', tmpfile.path, callback, cipher)
    decrypted = `openssl enc -d -#{cipher} -pass pass:#{PASSPHRASE} -in #{tmpfile.path}`
    assert_equal(plaintext, decrypted)

    # Test encrypting on a directory
    Dir.mktmpdir('testdir') do |testdir|
      File.open(File.join(testdir, 'file1'), 'w') do |file|
        file.write(plaintext)
      end
      File.open(File.join(testdir, 'file2'), 'w') do |file|
        file.write(plaintext)
      end
      Tpkg::encrypt('tpkgtest', testdir, PASSPHRASE, cipher)
      decrypted = `openssl enc -d -#{cipher} -pass pass:#{PASSPHRASE} -in #{File.join(testdir, 'file1')}`
      assert_equal(plaintext, decrypted)
      decrypted = `openssl enc -d -#{cipher} -pass pass:#{PASSPHRASE} -in #{File.join(testdir, 'file2')}`
      assert_equal(plaintext, decrypted)
    end
    
    # Test encrypting an empty file
    File.open(tmpfile.path, 'w') do |file|
    end
    Tpkg::encrypt('tpkgtest', tmpfile.path, callback, cipher)
  end
  
  def test_decrypt
    plaintext = 'This is the plaintext'
    cipher = 'aes-256-cbc'
    
    tmpfile = Tempfile.new('tpkgtest')
    tmpfile.close
    File.chmod(0604, tmpfile.path)
    
    # Test decrypt
    IO.popen(
      "openssl enc -#{cipher} -salt -pass pass:#{PASSPHRASE} -out #{tmpfile.path}",
      'w') do |pipe|
      pipe.write(plaintext)
    end
    Tpkg::decrypt('tpkgtest', tmpfile.path, PASSPHRASE, cipher)
    decrypted = IO.read(tmpfile.path)
    assert_equal(plaintext, decrypted)
    assert_equal(0604, File.stat(tmpfile.path).mode & 07777)
    
    # Test using a callback to supply the passphrase
    IO.popen(
      "openssl enc -#{cipher} -salt -pass pass:#{PASSPHRASE} -out #{tmpfile.path}",
      'w') do |pipe|
      pipe.write(plaintext)
    end
    callback = lambda { |pkgname| PASSPHRASE }
    Tpkg::decrypt('tpkgtest', tmpfile.path, callback, cipher)
    decrypted = IO.read(tmpfile.path)
    assert_equal(plaintext, decrypted)

    # Test decrypting on a directory
    Dir.mktmpdir('testdir') do |testdir|
      IO.popen(
        "openssl enc -#{cipher} -salt -pass pass:#{PASSPHRASE} -out #{File.join(testdir, 'file1')}",
        'w') do |pipe|
        pipe.write(plaintext)
      end
      Tpkg::decrypt('tpkgtest', testdir, PASSPHRASE, cipher)
      decrypted = IO.read(File.join(testdir, 'file1'))
      assert_equal(plaintext, decrypted)
    end
    
    # Test decrypting an empty file
    IO.popen(
      "openssl enc -#{cipher} -salt -pass pass:#{PASSPHRASE} -out #{tmpfile.path}",
      'w') do |pipe|
    end
    Tpkg::decrypt('tpkgtest', tmpfile.path, callback, cipher)
  end
  
  def test_verify_precrypt_file
    plaintext = 'This is the plaintext'
    cipher = 'aes-256-cbc'
    
    tmpfile = Tempfile.new('tpkgtest')
    tmpfile.close
    
    IO.popen(
      "openssl enc -#{cipher} -salt -pass pass:#{PASSPHRASE} -out #{tmpfile.path}",
      'w') do |pipe|
      pipe.write(plaintext)
    end
    
    assert(Tpkg::verify_precrypt_file(tmpfile.path))
    
    File.open(tmpfile.path, 'w') do |file|
      file.puts plaintext
    end
    
    assert_raise(RuntimeError) { Tpkg::verify_precrypt_file(tmpfile.path) }
  end
end
