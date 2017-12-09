# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::SubclassTracking do
  describe ".recursive_subclasses" do
    it "registers all created projects and subclasses" do
      Kennel::Models::Project.recursive_subclasses.must_equal [TestProject, SubTestProject]
    end
  end
end
