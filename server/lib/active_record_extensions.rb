module ActiveRecordExtensions
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def find_or_create(params)

      begin
        return self.find(params[:id])
      rescue ActiveRecord::RecordNotFound => e
        attrs = {}

        # search for valid attributes in params
        self.column_names.map(&:to_sym).each do |attrib|
          what =  {"name"=>"package 3", "os"=>"linux", "version"=>"12.3.4"}
          puts "In here and attrib is #{attrib}"
          # skip unknown columns, and the id field
          next if params[attrib.to_s].nil? || attrib == :id
          attrs[attrib.to_s] = params[attrib.to_s]
        end

puts "here is the attrs #{attrs.inspect}"

        # call the appropriate ActiveRecord finder method
        found = self.send("find_by_#{attrs.keys.join('_and_')}", *attrs.values) if !attrs.empty?
        if found && !found.nil?
          return found
        else
          return self.create(params)
        end
      end
    end
    alias create_or_find find_or_create
  end
end

ActiveRecord::Base.send(:include, ActiveRecordExtensions)
