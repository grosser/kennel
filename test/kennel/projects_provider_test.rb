# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::ProjectsProvider do
  def write(file, content)
    folder = File.dirname(file)
    FileUtils.mkdir_p folder
    File.write file, content
  end

  in_temp_dir
  capture_all
  without_cached_projects

  let(:kennel) { Kennel::Engine.new }

  after do
    Kennel::Models::Project.recursive_subclasses.each do |klass|
      if defined?(klass.name.to_sym)
        path = klass.name.split("::")
        path[0...-1].inject(Object) { |mod, name| mod.const_get(name) }.send(:remove_const, path.last.to_sym)
      end
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

    projects = Kennel::ProjectsProvider.new.projects.map(&:name)
    projects.must_equal ["Project1"]
  end

  it "avoids loading twice" do
    write "projects/project1.rb", <<~RUBY
      class Project1 < Kennel::Models::Project
        defaults(
          team: Kennel::Models::Team.new,
          kennel_id: 'p1',
          parts: [],
        )
      end
    RUBY

    Zeitwerk::Loader.any_instance.expects(:setup).times(1)
    Zeitwerk::Loader.any_instance.expects(:eager_load).times(1)

    2.times do
      Kennel::ProjectsProvider.new.projects.map(&:name).must_equal ["Project1"]
    end
  end

  it "shows helpful autoload errors for parts" do
    write "projects/a.rb", <<~RUBY
      class TestProject3 < Kennel::Models::Project
        FooBar::BazFoo
      end
    RUBY
    e = assert_raises(NameError) { kennel.generate }
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
    e = assert_raises(NameError) { kennel.generate }
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
    e = assert_raises(NameError) { kennel.generate }
    e.message.must_equal <<~MSG.rstrip
      wut
    MSG
  end

  describe "autoload" do
    with_env AUTOLOAD_PROJECTS: "1"

    before do
      2.times do |i|
        write "projects/project#{i}.rb", <<~RUBY
          class Project#{i} < Kennel::Models::Project
          end
        RUBY
      end
    end

    it "can load a single project" do
      with_env PROJECT: "project1" do
        projects = Kennel::ProjectsProvider.new.projects.map(&:name)
        projects.must_equal ["Project1"]
      end
    end

    it "can load a single project that has it's own folder" do
      write "projects/projecta/project.rb", <<~RUBY
        module Projecta
          class Project < Kennel::Models::Project
          end
        end
      RUBY

      with_env PROJECT: "project2" do
        projects = Kennel::ProjectsProvider.new.projects.map(&:name)
        projects.must_include "Projecta::Project"
      end
    end

    it "warns when autoloading a single project did not work" do
      with_env PROJECT: "projectx" do
        Kennel.err.expects(:puts)
        projects = Kennel::ProjectsProvider.new.projects.map(&:name)
        projects.must_include "Project1"
      end
    end

    it "can load all project" do
      _projects = Kennel::ProjectsProvider.new.projects.map(&:name)
      # TODO: this only works when running 1 test and not all
      # projects.must_equal ["Project0", "Project1"]
    end
  end
end
