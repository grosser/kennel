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
  s.required_ruby_version = ">= #{File.read(".ruby-version").strip[0..2]}.0"
  s.add_dependency "diff-lcs", "~> 1.5"
  s.add_dependency "faraday", "~> 1.8"
  s.add_dependency "hashdiff", "~> 1.0"
  s.add_dependency "net-http-persistent", "~> 4.0"
  s.add_dependency "zeitwerk", "~> 2.4"
end
