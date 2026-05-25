# frozen_string_literal: true

namespace :kennel do
  desc "Resolve given id to kennel tracking-id RESOURCE= ID="
  task tracking_id: "kennel:environment" do
    resource = ENV.fetch("RESOURCE")
    id = ENV.fetch("ID")
    klass =
      Kennel::Models::Record.subclasses.detect { |s| s.api_resource == resource } ||
      raise("resource #{resource} not know")
    object = Kennel::Api.new.show(resource, id)
    Kennel.out.puts klass.parse_tracking_id(object)
  end
end
