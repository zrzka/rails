# frozen_string_literal: true

require "generators/generators_test_helper"
require "generators/action_text/install/install_generator"

module Webpacker
  extend self

  def config
    Class.new do
      def source_path
        "app/packs"
      end

      def source_entry_path
        "app/packs/entrypoints"
      end
    end.new
  end
end

class ActionText::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  setup do
    Rails.application = Rails.application.class
    Rails.application.config.root = Pathname(destination_root)
    run_under_webpacker
  end

  teardown do
    Rails.application = Rails.application.instance
    run_under_asset_pipeline
  end

  test "installs JavaScript dependencies" do
    run_generator_instance
    yarn_commands = @yarn_commands.join("\n")

    assert_match %r"^add .*@rails/actiontext@", yarn_commands
    assert_match %r"^add .*trix@", yarn_commands
  end

  test "throws warning for incomplete webpacker configuration" do
    output = run_generator_instance
    expected = "WARNING: Action Text can't locate your JavaScript bundle to add its package dependencies."

    assert_match expected, output
  end

  test "loads JavaScript dependencies in application.js" do
    application_js = Pathname("app/javascript/application.js").expand_path(destination_root)
    application_js.dirname.mkpath
    application_js.write("\n")

    run_under_asset_pipeline
    run_generator_instance

    assert_file application_js do |content|
      assert_match %r"^#{Regexp.escape 'import "@rails/actiontext"'}", content
      assert_match %r"^#{Regexp.escape 'import "trix"'}", content
    end
  end

  test "creates Action Text stylesheet" do
    run_generator_instance

    assert_file "app/assets/stylesheets/actiontext.scss"
  end

  test "creates Active Storage view partial" do
    run_generator_instance

    assert_file "app/views/active_storage/blobs/_blob.html.erb"
  end

  test "creates Action Text content view layout" do
    run_generator_instance

    assert_file "app/views/layouts/action_text/contents/_content.html.erb"
  end

  test "creates migrations" do
    run_generator_instance

    assert_migration "db/migrate/create_active_storage_tables.active_storage.rb"
    assert_migration "db/migrate/create_action_text_tables.action_text.rb"
  end

  test "uncomments image_processing gem" do
    gemfile = Pathname("Gemfile").expand_path(destination_root)
    gemfile.dirname.mkpath
    gemfile.write(%(# gem "image_processing"))

    run_generator_instance

    assert_file gemfile do |content|
      assert_equal %(gem "image_processing"), content
    end
  end

  test "run just for asset pipeline" do
    run_under_asset_pipeline

    application_js = Pathname("app/javascript/application.js").expand_path(destination_root)
    application_js.dirname.mkpath
    application_js.write ""

    run_generator_instance

    assert_file application_js do |content|
      assert_match %r"trix", content
    end
  end

  private
    def run_generator_instance
      @yarn_commands = []
      yarn_command_stub = -> (command, *) { @yarn_commands << command }

      generator.stub :yarn_command, yarn_command_stub do
        with_database_configuration { super }
      end
    end

    def run_under_webpacker
      # Stub Webpacker engine presence to exercise path
      Kernel.silence_warnings { Webpacker.const_set(:Engine, true) } rescue nil
    end

    def run_under_asset_pipeline
      Kernel.silence_warnings { Webpacker.send(:remove_const, :Engine) } rescue nil
    end
end
