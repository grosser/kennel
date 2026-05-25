# frozen_string_literal: true

namespace :kennel do
  desc "Convert existing resources to copy-pasteable definitions to import existing resources (call with URL= or call with RESOURCE= and ID=)"
  task import: :environment do
    if (id = ENV["ID"]) && (resource = ENV["RESOURCE"])
      id = Integer(id) if id =~ /^\d+$/
    elsif (url = ENV["URL"])
      resource, id = Kennel::Models::Record.parse_any_url(url) || Kennel::Tasks.abort("Unable to parse url")
    else
      possible_resources = Kennel::Models::Record.subclasses.map(&:api_resource)
      Kennel::Tasks.abort("Call with URL= or call with RESOURCE=#{possible_resources.join(" or ")} and ID=")
    end

    Kennel.out.puts Kennel::Importer.new(Kennel::Api.new).import(resource, id)
  end
end
