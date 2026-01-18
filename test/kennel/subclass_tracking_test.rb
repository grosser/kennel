# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::SubclassTracking do
  define_test_classes

  describe ".recursive_subclasses" do
    it "registers all created projects and subclasses" do
      Kennel::Models::Project.recursive_subclasses.must_equal [TestProject, SubTestProject]
    end
  end

  describe ".abstract_class!" do
    it "marks self but not subclasses" do
      parent = Class.new(Kennel::Models::Project)
      parent.send(:abstract_class!)
      assert parent.abstract_class?

      begin
        child = Class.new(parent)
        refute child.abstract_class?

        refute Kennel::Models::Project.abstract_class?
      ensure
        Kennel::Models::Project.subclasses.delete(child)
      end
    ensure
      Kennel::Models::Project.subclasses.delete(parent)
    end
  end
end
