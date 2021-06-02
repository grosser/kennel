require 'json'
require 'tempfile'

module Kennel
  class Resources
    def self.each(resources: nil)
      return enum_for(resources: resources) unless block_given?

      resources ||= Kennel::Models::Record.api_resource_map.keys
      api = Kennel.send(:api)
      list = nil

      resources.each do |resource|
        Kennel::Progress.progress("Downloading #{resource}") do
          list = api.list(resource)
          api.fill_details!(resource, list)
        end

        list.each do |r|
          r[:api_resource] = resource
          yield r
        end
      end
    end

    def self.cached_each(filename:, max_age:, &block)
      return enum_for(:cached_each, filename: filename, max_age: max_age) unless block_given?

      File.open(filename, 'r') do |f|
        age = (Time.now - f.stat.mtime)
        raise Errno::ENOENT if age > max_age
        Kennel.err.puts "Using #{age.to_i}-seconds-old #{filename}"
        f.each_line do |line|
          block.call(JSON.parse(line, symbolize_names: true))
        end
      end

      nil
    rescue Errno::ENOENT
      Tempfile.open(filename, File.dirname(filename)) do |f|
        each do |r|
          f.puts(JSON.generate(r))
          block.call(r)
        end

        f.flush
        f.chmod 0o644
        File.rename f.path, filename
      end

      Kennel.err.puts "Saved results to #{filename}"

      nil
    end
  end
end
