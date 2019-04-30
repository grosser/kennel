# frozen_string_literal: true
name = "kennel"
$LOAD_PATH << File.expand_path("lib", __dir__)
require "#{name}/version"

Gem::Specification.new name, Kennel::VERSION do |s|
  s.summary = "Keep datadog monitors/dashboards/etc in version control, avoid chaotic management via UI"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib Readme.md template/Readme.md`.split("\n")
  s.license = "MIT"
  s.required_ruby_version = ">= 2.5.0"
  s.add_runtime_dependency "faraday"
  s.add_runtime_dependency "hashdiff"
  s.add_runtime_dependency "net-http-persistent-retry"
end
