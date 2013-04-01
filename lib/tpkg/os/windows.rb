# tpkg package management system
# License: MIT (http://www.opensource.org/licenses/mit-license.php)

class Tpkg::OS::Windows < Tpkg::OS
  def self.supported?
    Facter.loadfacts
    Facter['operatingsystem'].value == 'windows'
  end
  register_implementation(self)
  
  def os_version
    if !@os_version
      # Extract 6.1 from 6.1.7601, for example
      # That seems like the right level to split at
      # based on http://en.wikipedia.org/wiki/Ver_(command)
      winver = Facter['operatingsystemrelease'].value
      @os_version = winver.split('.')[0,2].join('.')
    end
    super
  end
  
  def sudo_default?
    # Neither of the common Windows environments for running Ruby have sudo
    return false
  end
end
