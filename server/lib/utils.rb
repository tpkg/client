  def parse_xml_package(xml, root="")
    #puts xml
    packages = Array.new
    doc = REXML::Document.new(xml)
    doc.elements.each("#{root}tpkg/") do |ele|
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
