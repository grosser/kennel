# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::ProjectsGenerator do
  def write(file, content)
    folder = File.dirname(file)
    FileUtils.mkdir_p folder unless File.exist?(folder)
    File.write file, content
  end

  in_temp_dir
  capture_all

  after do
    Kennel::Models::Project.recursive_subclasses.each do |klass|
      p klass
      Object.send(:remove_const, klass.name.to_sym) if defined?(klass.name.to_sym)
    end
    Kennel::Models::Project.subclasses.delete_if { true }
  end

  it "loads projects" do
    write "teams/my_team.rb", <<~TEAM
      class Teams::MyTeam < Kennel::Models::Team
        defaults(
          mention: "@slack-some-channel",
        )
      end
    TEAM

    write "projects/project1.rb", <<~RUBY
      class Project1 < Kennel::Models::Project
        defaults(
          team: Teams::MyTeam.new,
          kennel_id: 'p1',
          parts: [],
        )
      end
    RUBY

    projects = Kennel::ProjectsGenerator.new.projects.map(&:name)
    projects.must_equal ['Project1']
  end

  it "shows helpful autoload errors for parts" do
    write "projects/a.rb", <<~RUBY
        class TestProject3 < Kennel::Models::Project
          FooBar::BazFoo
        end
    RUBY
    e = assert_raises(NameError) { Kennel.generate }
    e.message.must_equal("\n" + <<~MSG.gsub(/^/, "  "))
        uninitialized constant TestProject3::FooBar
        Unable to load TestProject3::FooBar from parts/test_project3/foo_bar.rb
        - Option 1: rename the constant or the file it lives in, to make them match
        - Option 2: Use `require` or `require_relative` to load the constant
    MSG
  end

  it "shows helpful autoload errors for teams" do
    write "projects/a.rb", <<~RUBY
        class TestProject4 < Kennel::Models::Project
          Teams::BazFoo
        end
    RUBY
    e = assert_raises(NameError) { Kennel.generate }
    e.message.must_equal("\n" + <<~MSG.gsub(/^/, "  "))
        uninitialized constant Teams::BazFoo
        Unable to load Teams::BazFoo from teams/baz_foo.rb
        - Option 1: rename the constant or the file it lives in, to make them match
        - Option 2: Use `require` or `require_relative` to load the constant
    MSG
  end

  it "shows unparseable NameError" do
    write "projects/a.rb", <<~RUBY
        class TestProject5 < Kennel::Models::Project
          raise NameError, "wut"
        end
    RUBY
    e = assert_raises(NameError) { Kennel.generate }
    e.message.must_equal "wut"
  end
end
