class PkgUtils
  def self.parse_xml_package(xml)
    #puts xml
    packages = Array.new
    doc = REXML::Document.new(xml)
    doc.elements.each('packages/tpkg/') do |ele|
      package = Hash.new
      package["name"] = ele.elements["name"].text
      package["version"] = ele.elements["version"].text
      package["os"] = ele.elements["operatingsystem"].text if ele.elements["operatingsystem"]
      package["arch"] = ele.elements["architecture"].text if ele.elements["architecture"]
      package["maintainer"] = ele.elements["maintainer"].text
      package["description"] = ele.elements["description"].text if ele.elements["description"]
      package["package_version"] = ele.elements["package_version"].text if ele.elements["package_version"]
      package["filename"] = ele.attributes["filename"]
      packages << package
    end
    return packages
  end

#  PKG_ATTR = [:name, :version, :os, :arch, :maintainer, :description, :package_version, :filename]
  def self.metadata_to_db_package(metadata)
    package = Hash.new
    package["name"] = metadata[:name]
    package["version"] = metadata[:version]
    package["os"] = metadata[:operatingsystem].join(",") if metadata[:operatingsystem]
    package["arch"] = metadata[:architecture].join(",") if metadata[:architecture]
    package["maintainer"] = metadata[:maintainer]
    package["description"] = metadata[:description] if metadata[:description]
    package["package_version"] = metadata[:package_version] if metadata[:package_version]
    package["filename"] = metadata[:filename]
    return package
  end

  def self.parse_yml_packages(yml)
    packages = Array.new
    packages_yaml = YAML::load(yml)
    packages_yaml.each do |pkg|
      packages << metadata_to_db_package(pkg)
    end
    return packages
  end

  # Given an array of packages metadata hash (in yaml string format), return back an array
  # of Packages. Create new Package object in the Package table if it's not there
  def self.pkgs_metadata_to_db_objects(yml)
    packages = Array.new
    packages_yaml = YAML::load(yml)
    packages_yaml.each do |metadata|
      pkg = metadata_to_db_package(metadata)
      packages << Package.find_or_create(pkg)
    end
    return packages
  end
end
